{
  description = "mvm microVM — single-node Kubernetes (k3s, rootless)";

  # EXPERIMENTAL scaffold: the image builds and boots, but the rootless k3s
  # bring-up is validated by the smoke test tracked in the mvm repo's
  # Kubernetes-in-microVM plan (W4). See README.md in this directory for the
  # constraints and the open items.
  inputs = {
    mvm.url = "github:tinylabscom/mvm?dir=nix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { mvm, nixpkgs, ... }:
    let
      system = "aarch64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Single-node k3s, rootless under the mvm workload uid.
      #
      # Networking contract of the guest (see README.md): there is no guest
      # NIC and no TAP/TUN. PID 1 exports ALL_PROXY / HTTP_PROXY /
      # HTTPS_PROXY pointing at the vsock egress proxy on loopback
      # (socks5h://127.0.0.1:1080), and only admitted host:port flows tunnel
      # to the host. Cluster-internal traffic (apiserver, pods, services) is
      # ordinary in-guest netns/bridge traffic and needs no NIC. RootlessKit
      # therefore runs with --net=host: there is no upstream interface for a
      # slirp4netns-style userspace stack to speak to.
      startScript = pkgs.writeShellScript "k3s-rootless-start" ''
        set -eu

        DATA_DIR=/data/k3s
        KUBECONFIG_OUT=''${KUBECONFIG_OUT:-/data/k3s/k3s.yaml}

        if ! grep -q " /data " /proc/mounts; then
          echo "k3s-rootless-start: /data is not mounted; attach a :rw disk" >&2
          echo "  volume, e.g. --mount ./k3s-data:/data:20G:rw" >&2
          exit 1
        fi
        mkdir -p "$DATA_DIR"

        # Proxy env (ALL_PROXY/HTTP_PROXY/HTTPS_PROXY) is inherited from PID 1:
        # container image pulls and other outbound HTTPS ride the vsock egress
        # proxy, and only allow_hosts-admitted destinations are tunneled.
        #
        # Rootless single-node server. --disable keeps the control plane lean
        # for the dev/test tier this targets; add traefik/servicelb back when
        # ingress is needed (host reachability then goes through a declared
        # --port ingress forward, not a NodePort on a NIC).
        exec ${pkgs.rootlesskit}/bin/rootlesskit \
          --net=host --ipc=host --uts=host \
          ${pkgs.k3s}/bin/k3s server \
          --rootless \
          --data-dir="$DATA_DIR" \
          --write-kubeconfig="$KUBECONFIG_OUT" \
          --write-kubeconfig-mode=600 \
          --disable=traefik,servicelb
      '';

      kubectlWithConfig = pkgs.writeShellScriptBin "kubectl" ''
        exec ${pkgs.k3s}/bin/k3s kubectl --kubeconfig /data/k3s/k3s.yaml "$@"
      '';
    in
    {
      packages.${system}.default = mvm.lib.${system}.mkGuest {
        name = "kubernetes-vm";

        # Sized for a control plane: 4 vCPU / 4 GiB. Container image storage
        # consumes the /data disk volume, not the read-only rootfs.
        vcpus = 4;
        memory_mib = 4096;

        packages = [
          pkgs.k3s
          pkgs.rootlesskit
          kubectlWithConfig
        ];

        extraFiles."/usr/local/bin/k3s-rootless-start" = {
          source = startScript;
          mode = "0755";
        };

        entrypoint.command = [ "/usr/local/bin/k3s-rootless-start" ];

        # Declared to the guest agent's probe loop; the agent runs the drop-in
        # and serves ProbeStatus over vsock. Readiness = this node is Ready.
        healthChecks.node-ready = {
          healthCmd = "${pkgs.k3s}/bin/k3s kubectl --kubeconfig /data/k3s/k3s.yaml get nodes --no-headers | grep -q Ready";
          healthIntervalSecs = 10;
          healthTimeoutSecs = 15;
        };
      };
    };
}
