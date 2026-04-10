# K3s Cluster Module
# Replaces: kubernetes.nix (729 lines), kubernetes-ha.nix (270 lines), etcd-cluster.nix (120 lines)
#
# K3s bundles into a single binary:
#   kube-apiserver, kubelet, kube-scheduler, kube-controller-manager,
#   kube-proxy, etcd (embedded), containerd, CoreDNS
# Auto-TLS eliminates the entire PKI/certs infrastructure.
#
# Architecture:
#   Zephyr: server + embedded etcd (clusterInit = true, bootstrap)
#   Nexus:  server + embedded etcd (joins existing cluster)
#   Sentry: server + embedded etcd (joins existing cluster)
#   Forge:  agent (worker only)
#
# CNI: Flannel (default) or Calico (via calico.enable)
# Ingress: Caddy DaemonSet (unchanged)
# HA: Keepalived VIP (unchanged)
#
# IMPORTANT: All servers must share identical values for --cluster-cidr,
# --service-cidr, --disable list, and --disable-network-policy.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.k3s-cluster;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkMerge
    mkDefault
    ;

  inherit (lib) mkOptionDefault;

  isServer = cfg.role == "server";

  # Shared CIDR ranges — MUST be identical across all servers
  clusterCIDR = "10.244.0.0/16";
  serviceCIDR = "10.0.0.0/12";
  clusterDNS = "10.0.0.10";

  # TLS SANs — all server IPs and hostnames
  tlsSans = [
    "10.1.1.100" # VIP
    "10.1.1.110" # Zephyr
    "10.1.1.120" # Nexus
    "10.1.1.130" # Forge
    "10.1.1.140" # Sentry
    "zephyr"
    "nexus"
    "forge"
    "sentry"
    "kubernetes"
    "kubernetes.default"
    "kubernetes.default.svc"
    "kubernetes.default.svc.cluster.local"
    "cluster.local"
    "localhost"
    "127.0.0.1"
  ];

  # Components to disable on all servers (identical list required)
  disabledComponents = [
    "traefik" # We use Caddy ingress DaemonSet
    "servicelb" # We use Caddy with hostPort
    "metrics-server" # We deploy our own
  ];

in
{
  options.services.k3s-cluster = {
    enable = mkEnableOption "k3s lightweight Kubernetes cluster";

    role = mkOption {
      type = types.enum [
        "server"
        "agent"
      ];
      default = "agent";
      description = "k3s node role: server (control plane + workloads) or agent (workloads only)";
    };

    clusterInit = mkOption {
      type = types.bool;
      default = false;
      description = "Set true on the first server to bootstrap a new HA cluster with embedded etcd";
    };

    clusterReset = mkOption {
      type = types.bool;
      default = false;
      description = "Set true once to reset cluster (clear corrupted state), then set false";
    };

    serverAddr = mkOption {
      type = types.str;
      default = "https://10.1.1.100:6443";
      description = "k3s server URL for agents and joining servers (VIP for HA)";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File containing the k3s cluster token (agenix secret)";
    };

    nodeIP = mkOption {
      type = types.str;
      default = "";
      description = "IP address to advertise for this node";
    };

    nodeName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Kubernetes node name (defaults to hostname)";
    };

    calico = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Use Calico CNI instead of k3s default Flannel. Adds --flannel-backend=none and --disable-network-policy.";
      };
    };

    nvidia = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Configure NVIDIA containerd runtime for GPU workloads";
      };
    };
  };

  config = mkIf cfg.enable {
    services.k3s = {
      enable = true;
      inherit (cfg) role nodeName;

      package = pkgs.k3s_1_34;

      # HA cluster init (first server only)
      clusterInit = if isServer then cfg.clusterInit else false;

      # Server address for agents and joining servers
      # Ignored if etcd data exists on disk (k3s always rejoins existing cluster)
      serverAddr = if (!isServer || !cfg.clusterInit) then cfg.serverAddr else "";

      # Token file for cluster join — only set when joining existing cluster
      # When clusterInit=true, K3s generates its own token
      tokenFile = if cfg.clusterInit then null else cfg.tokenFile;

      # Node IP advertisement
      nodeIP = if cfg.nodeIP != "" then cfg.nodeIP else null;

      # Disable k3s bundled components (server role only)
      # When calico.enable = true, also disable flannel and k3s network-policy
      # (Calico provides its own network policy engine)
      disable =
        lib.optionals isServer disabledComponents
        ++ lib.optionals (isServer && cfg.calico.enable) [
          "flannel"
          "network-policy"
          "kube-proxy" # Calico handles service proxy via kube-router
        ];

      # Extra flags — server role only
      extraFlags =
        lib.optionals isServer (
          [
            "--cluster-cidr=${clusterCIDR}"
            "--service-cidr=${serviceCIDR}"
            "--cluster-dns=${clusterDNS}"
            "--write-kubeconfig-mode=644"
          ]
          ++ map (san: "--tls-san=${san}") tlsSans
          ++ lib.optional cfg.calico.enable "--flannel-backend=none"
        )
        # Node labels for GPU scheduling
        ++ lib.optional config.hardware.nvidia-common.enable "--node-label=accelerator=nvidia-gpu"
        ++ lib.optional (config.hardware.gpu-compute.rocm.enable or false) "--node-label=gpu=amd";

      # NVIDIA containerd runtime configuration
      # Must include {{ template "base" . }} to preserve k3s defaults
      containerdConfigTemplate = mkIf cfg.nvidia.enable ''
        {{ template "base" . }}
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
            BinaryName = "${pkgs.nvidia-container-toolkit.tools}/bin/nvidia-container-runtime"
      '';

      # Extra kubelet configuration
      extraKubeletConfig = {
        failSwapOn = false;
      };

      # Run workloads on servers too
      disableAgent = false;
    };

    # FIREWALL RULES
    networking.firewall = mkMerge [
      {
        allowedTCPPorts = mkOptionDefault (
          [ 10250 ] # Kubelet API
          ++ lib.optionals isServer [
            6443 # k3s API server
            2379 # Embedded etcd client
            2380 # Embedded etcd peer
          ]
          ++ lib.optionals cfg.calico.enable [
            179 # Calico BGP
            5473 # Calico Typha
          ]
        );
        allowedTCPPortRanges = [
          {
            from = 30000;
            to = 32767;
          } # NodePort range
        ];
        allowedUDPPorts = mkOptionDefault (
          lib.optionals (!cfg.calico.enable) [
            8472
          ]
          ++ [
            4789
          ]
        ); # Flannel VXLAN or Calico VXLAN
      }
    ];

    # SYSTEM PACKAGES
    environment.systemPackages =
      with pkgs;
      [
        kubernetes # kubectl and other tools
        cri-tools # crictl for CRI debugging
        iptables # iptables-save/restore for Calico CNI compatibility
        runc # nvidia-container-runtime needs runc in PATH
      ]
      ++ lib.optionals cfg.nvidia.enable [
        nvidia-container-toolkit
        nvidia-container-toolkit.tools
      ];

    # KUBERNETES CLI ALIASES
    programs.bash.shellAliases = {
      k = "kubectl";
      kgp = "kubectl get pods";
      kgs = "kubectl get svc";
      kgd = "kubectl get deploy";
      kga = "kubectl get all";
      kgns = "kubectl get namespaces";
      kgn = "kubectl get nodes";
    };
    programs.fish.shellAliases = {
      k = "kubectl";
      kgp = "kubectl get pods";
      kgs = "kubectl get svc";
      kgd = "kubectl get deploy";
      kga = "kubectl get all";
      kgns = "kubectl get namespaces";
      kgn = "kubectl get nodes";
    };

    # KUBECONFIG symlink for easy access
    systemd.tmpfiles.rules = [
      "d /root/.kube 0700 root root -"
      "L /root/.kube/config - - - - /etc/rancher/k3s/k3s.yaml"
    ];

    # Disable NRI (Node Runtime Interface) to prevent nri-wait hook
    # from blocking container creation with 30s timeout.
    # The nri-wait hook expects a Nix build system to publish build
    # status via ZeroMQ sockets at /nix/var/nixkube/.
    # Since we don't use Nix builds for containers, disable NRI entirely.
    systemd.services.k3s.environment.CONTAINERD_NRI_DISABLED = "1";

    # Ensure k3s containerd state directories exist
    system.activationScripts.k3s-dirs = ''
      mkdir -p /var/lib/rancher/k3s/agent/etc/containerd
    '';

    # Workaround: k3s host-gw mode doesn't clear NetworkUnavailable condition
    # The kubelet sets NetworkUnavailable=True on startup, but k3s's embedded
    # cloud-controller-manager doesn't set it to False for host-gw backend.
    # This timer patches the condition and removes the taint every 30s.
    # See: k3s-io/k3s#2808
    systemd.services.k3s-network-taint-fix = lib.mkIf isServer {
      description = "Fix NetworkUnavailable taint for host-gw flannel";
      path = [ pkgs.kubectl ];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = pkgs.writeShellScript "fix-network-taint" ''
        export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
        for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
          kubectl patch node "$node" --type=merge \
            -p '{"status":{"conditions":[{"type":"NetworkUnavailable","status":"False","reason":"FlannelHostGWIsUp","message":"Flannel host-gw routes active"}]}}' \
            --subresource=status 2>/dev/null || true
          kubectl taint nodes "$node" node.kubernetes.io/network-unavailable:NoSchedule- 2>/dev/null || true
        done
      '';
    };
    systemd.timers.k3s-network-taint-fix = lib.mkIf isServer {
      description = "Periodically fix NetworkUnavailable taint";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30s";
        AccuracySec = "10s";
      };
    };
  };
}
# Force rebuild Tue 07 Apr 2026 03:12:49 AM CDT
