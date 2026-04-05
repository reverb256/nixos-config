# K3s Cluster Module
# Replaces: kubernetes.nix (729 lines), kubernetes-ha.nix (270 lines), etcd-cluster.nix (120 lines)
# Net change: ~1200 lines deleted, ~180 lines new
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
# CNI: Calico (BGP) - disable k3s default Flannel
# Ingress: Caddy DaemonSet (unchanged from vanilla K8s)
# HA: Keepalived VIP (unchanged)
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
  useCalico = cfg.calico.enable;
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
        default = true;
        description = "Use Calico CNI instead of k3s default Flannel";
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
      serverAddr = if (!isServer || !cfg.clusterInit) then cfg.serverAddr else "";

      # Token file for cluster join - only set when joining existing cluster
      # When clusterInit=true, K3s generates its own token
      tokenFile = if cfg.clusterInit then null else cfg.tokenFile;

      # Node IP advertisement
      nodeIP = if cfg.nodeIP != "" then cfg.nodeIP else null;

      # Disable k3s bundled components we don't need (server role only)
      # NOTE: Keeping flannel enabled initially - will switch to Calico once cluster is stable
      disable = lib.optionals (isServer) [
        "traefik" # We use Caddy ingress DaemonSet
        "servicelb" # We use Caddy with hostPort
        "metrics-server" # We deploy our own
        # "flannel" # Disabled - keeping enabled to bootstrap cluster
      ];

      # Extra flags - server role only
      # NOTE: Keeping flannel enabled initially to bootstrap cluster
      # Calico can be deployed once nodes are Ready
      extraFlags =
        lib.optionals isServer [
          "--cluster-cidr=10.244.0.0/16"
          "--service-cidr=10.0.0.0/12"
          "--write-kubeconfig-mode=644"
          # NOTE: Removed --endpoint-reconciler-type=none to allow proper kubernetes endpoints
          # reconciliation for HA API server access
          "--tls-san=10.1.1.100"
          "--tls-san=10.1.1.110"
          "--tls-san=10.1.1.120"
          "--tls-san=10.1.1.140"
          "--tls-san=zephyr"
          "--tls-san=nexus"
          "--tls-san=sentry"
          "--tls-san=kubernetes"
          "--tls-san=kubernetes.default"
          "--tls-san=kubernetes.default.svc"
          "--tls-san=kubernetes.default.svc.cluster.local"
          "--tls-san=cluster.local"
          "--tls-san=localhost"
          "--tls-san=127.0.0.1"
        ]
        # Node labels for GPU scheduling (use --node-label singular)
        ++ lib.optional config.hardware.nvidia-common.enable "--node-label=accelerator=nvidia-gpu"
        ++ lib.optional (config.hardware.gpu-compute.rocm.enable or false) "--node-label=gpu=amd"
      # Graceful shutdown - removed as it causes K3s 1.34 to fail
      # ++ [ "--kubelet-arg=--graceful-node-shutdown=true" ]
      ;

      # NVIDIA containerd runtime configuration
      containerdConfigTemplate = mkIf cfg.nvidia.enable ''
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
            BinaryName = "${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime"
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
          ++ lib.optionals useCalico [
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
        allowedUDPPorts = mkOptionDefault [
          8472
          4789
        ]; # VXLAN / Calico
      }
    ];

    # SYSTEM PACKAGES
    environment.systemPackages =
      with pkgs;
      [
        kubernetes # kubectl and other tools
        cri-tools # crictl for CRI debugging
      ]
      ++ lib.optional cfg.nvidia.enable nvidia-container-toolkit;

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
      # CNI config symlink - K3s writes to /var/lib/rancher/k3s/agent/etc/cni/net.d/
      # but kubelet expects it in /etc/cni/net.d/
      "d /etc/cni/net.d 0755 root root -"
      "L+ /etc/cni/net.d/10-flannel.conflist - - - - /var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist"
    ];

    # Ensure k3s containerd state directories exist
    system.activationScripts.k3s-dirs = ''
      mkdir -p /var/lib/rancher/k3s/agent/etc/containerd
    '';
  };
}
