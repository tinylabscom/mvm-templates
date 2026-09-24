# kubernetes template

Single-node Kubernetes (k3s, rootless) in one microVM. A whole cluster —
control plane and containerd together — is one disposable, digest-pinned
artifact: `mvmctl machine run` stands it up, `mvmctl machine stop` tears it
down.

**Status: experimental scaffold.** The image builds against the documented
`mkGuest` API. End-to-end bring-up, including the boot-image capability
contract required by rootless k3s, is tracked in tinylabscom/mvm-templates#1.

## The guest networking contract

The microVM has **no NIC and no TAP/TUN**. Everything that leaves the guest
rides the vsock egress plane:

- PID 1 exports `ALL_PROXY` / `HTTP_PROXY` / `HTTPS_PROXY` =
  `socks5h://127.0.0.1:1080`, the guest egress client tunneling admitted
  host:port flows to the host over FlowMux/vsock. Container image pulls and
  pod egress work only for `allow_hosts`-admitted destinations.
- Cluster-internal traffic (apiserver, pod-to-pod, service IPs) is ordinary
  in-guest netns/bridge traffic — no NIC needed.
- RootlessKit runs with `--net=host` (there is no upstream interface for a
  slirp4netns-style stack), and `traefik`/`servicelb` start disabled. Reach a
  workload from the host by declaring a signed ingress port at launch:
  `--port 8080:80`.
- The generated workload image must provide cgroups, namespaces, netfilter,
  and bridge/veth support. The template cannot select the host boot kernel via
  `mkGuest`: its `kernel` argument only supplies modules to the rootfs. The
  required image capability and end-to-end witness stay tracked in this
  repository rather than creating a Kubernetes-specific external image.
- The kubelet hard-requires `/dev/kmsg`; mvm's OCI device unpack allow-lists
  it and the guest kernel creates it via devtmpfs.

## Storage

Cluster state lives on a writable ext4 disk volume at `/data` (the rootfs is
read-only): attach one at launch, no hot-plug:

```sh
mvmctl machine run -d --name k8s --flake . \
  --mount ./k3s-data:/data:20G:rw \
  --allow-host registry-1.docker.io:443
```

k3s runs with `--data-dir=/data/k3s`; containerd state (including pulled
images) is under it, so the cluster survives reboots on the same volume.

## Driving the cluster

`mvmctl machine exec` and friends are DevOnly verbs — this is a dev/test
capability, refused by prod admission.

```sh
mvmctl machine exec k8s -- kubectl get nodes   # kubectl is on the guest PATH
```

## Relationship to the generic rootless tenant

mvm-images owns a generic rootless capability floor (the `rootless-tenant`
base and its `rootless` kernel: user/mount/PID/IPC/UTS namespaces, cgroup v2
delegation, PTYs, crun + fuse-overlayfs, no guest NIC — see the mvm-images
rootless image contract). This template builds on that contract but needs
**more kernel than the generic floor provides**: every pod sandbox is a
network namespace, so the guest kernel must also carry NET_NS plus the
in-guest pod datapath (bridge/veth, netfilter). The generic `rootless`
kernel deliberately omits NET_NS — it cannot host k3s. The template's
boot-image capability is therefore "rootless floor + in-guest network
namespaces", consumed via `mvmctl kernel build --which workload-k8s` today
(the capability lands under a generic name when the kernel canon completes
its move into mvm-images; tracked in tinylabscom/mvm-templates#1).

Everything external still leaves over the vsock egress plane; the in-guest
datapath carries only cluster-internal traffic.

### Boot-image capability: the `workload-k8s` kernel, and the invariant

The boot-image capability is "rootless floor + in-guest network
namespaces" (this template's pods are network namespaces). A generically
named `datapath` kernel posture (bridge/veth/netfilter in mvm-images) was
proposed and **rejected by the image lane**: guest network devices of any
kind violate the permanent mvm-images invariant (tinylabscom/mvm-images
PR #24, closed). The interim kernel remains mvm's in-repo
`workload-k8s` variant (tinylabscom/mvm#3572, consumed via
`mvmctl kernel build --which workload-k8s` and the dev-tier
`MVM_WORKLOAD_KERNEL_VARIANT` boot override from #3587).

The invariant-compatible durable shape is the one the mvm-images contract
itself names: **host networking inside the guest plus the injected loopback
egress proxy** — k3s runs with pod networking disabled and every external
byte still crosses the authenticated vsock session. What Kubernetes
semantics survive that shape (service addressing on loopback, port
allocation across pods) is an open design item for this template; the
cgroup2/uid/kmsg bring-up chain below is validated either way.

### Blocker status (2026-09-23): upstream kernel bug, not this template

tinylabscom/mvm#3599 — clone() failing inside a fresh PID namespace — is
resolved to root cause: a long-standing upstream kernel bug under
virtualization (reproduced under TCG, HVF, and x86_64 KVM; kernels 6.1
through 6.18; pristine userspace; independent hosts). Every pod sandbox is a
fresh PID namespace, so k3s pods cannot start on virtualized hosts until
upstream fixes it or an environmental precondition is found. The template's
bring-up chain (cgroup2 delegation, uid-901 identity, /dev/kmsg faking,
egress wiring) is validated; the node-level smoke test resumes when the
platform bug is resolved. See #3599 for the evidence matrix and the
ready-to-file upstream report draft.

## Open items the smoke test must settle

- RootlessKit single-uid mapping: whether k3s `--rootless` needs
  `newuidmap`/`newgidmap` + `/etc/sub{u,g}id` in this image, or runs in the
  single-mapping fallback.
- cgroup v2 delegation to the workload uid — without it kubelet cgroup
  accounting is degraded.
- `bridge-nf-call-iptables` sysctls: normally set by a privileged init; the
  workload uid cannot set them. In-guest pod/service rules that depend on it
  are part of the audit.
- Pod-network backend behavior with `--net=host` RootlessKit (flannel
  backend selection, CoreDNS upstream through the guest resolver).
