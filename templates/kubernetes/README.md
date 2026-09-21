# kubernetes template

Single-node Kubernetes (k3s, rootless) in one microVM. A whole cluster —
control plane and containerd together — is one disposable, digest-pinned
artifact: `mvmctl machine run` stands it up, `mvmctl machine stop` tears it
down.

**Status: experimental scaffold.** The image builds against the documented
`mkGuest` API; rootless bring-up inside the busybox PID-1 guest is validated
by the smoke test in the runtime plan (`specs/plans/2026-09-20-kubernetes-in-microvm.md`,
W4, in the `mvm` repo). Runtime tracking: tinylabscom/mvm#3554; kernel audit:
tinylabscom/mvm-images#9.

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

## Open items the smoke test must settle

- RootlessKit single-uid mapping: whether k3s `--rootless` needs
  `newuidmap`/`newgidmap` + `/etc/sub{u,g}id` in this image, or runs in the
  single-mapping fallback.
- cgroup v2 delegation to the workload uid (kernel audit, mvm-images#9) —
  without it kubelet cgroup accounting is degraded.
- `bridge-nf-call-iptables` sysctls: normally set by a privileged init; the
  workload uid cannot set them. In-guest pod/service rules that depend on it
  are part of the audit.
- Pod-network backend behavior with `--net=host` RootlessKit (flannel
  backend selection, CoreDNS upstream through the guest resolver).
