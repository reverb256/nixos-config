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

  clusterCIDR = "10.244.0.0/16";
  serviceCIDR = "10.0.0.0/12";
  clusterDNS = "10.0.0.10";

  tlsSans = [
    "10.1.1.100"
    "10.1.1.110"
    "10.1.1.120"
    "10.1.1.130"
    "10.1.1.140"
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

  disabledComponents = [
    "traefik"
    "servicelb"
    "metrics-server"
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
        description = "Use Calico CNI. Disables flannel, network-policy, and kube-proxy.";
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

      clusterInit = if isServer then cfg.clusterInit else false;

      serverAddr = if (!isServer || !cfg.clusterInit) then cfg.serverAddr else "";

      tokenFile = if cfg.clusterInit then null else cfg.tokenFile;

      nodeIP = if cfg.nodeIP != "" then cfg.nodeIP else null;

      disable =
        lib.optionals isServer disabledComponents
        ++ lib.optionals (isServer && cfg.calico.enable) [
          "flannel"
          "network-policy"
          "kube-proxy"
        ];

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
        ++ lib.optional config.hardware.nvidia-common.enable "--node-label=accelerator=nvidia-gpu"
        ++ lib.optional (config.hardware.gpu-compute.rocm.enable or false) "--node-label=gpu=amd"
        ++ lib.optional (cfg.nodeIP != "") "--node-external-ip=${cfg.nodeIP}";
        # --flannel-external-ip removed in k3s 1.34+ (upstream PR)
        # Flannel now auto-detects external IP from --node-external-ip

      containerdConfigTemplate = mkIf cfg.nvidia.enable ''
        {{ template "base" . }}
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
            BinaryName = "${pkgs.nvidia-container-toolkit.tools}/bin/nvidia-container-runtime"
      '';

      extraKubeletConfig = {
        failSwapOn = false;
      };

      disableAgent = false;
    };

    networking.firewall = mkMerge [
      {
        allowedTCPPorts = mkOptionDefault (
          [ 10250 ]
          ++ lib.optionals isServer [
            6443
            2379
            2380
          ]
          ++ lib.optionals cfg.calico.enable [
            179
            5473
          ]
        );
        allowedTCPPortRanges = [
          {
            from = 30000;
            to = 32767;
          }
        ];
        allowedUDPPorts = mkOptionDefault (
          lib.optionals (!cfg.calico.enable) [
            8472
          ]
          ++ [
            4789
          ]
        );
      }
    ];

    environment.systemPackages =
      with pkgs;
      [
        kubernetes
        cri-tools
        iptables
        runc
      ]
      ++ lib.optionals cfg.nvidia.enable [
        nvidia-container-toolkit
        nvidia-container-toolkit.tools
      ];

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

    systemd.tmpfiles.rules = [
      "d /root/.kube 0700 root root -"
      "L /root/.kube/config - - - - /etc/rancher/k3s/k3s.yaml"
    ];

    systemd.services.k3s = {
      environment.CONTAINERD_NRI_DISABLED = "1";
      # Start before keepalived so flannel detects the real IP, not the VIP
      before = lib.mkIf config.services.keepalived.enable [ "keepalived.service" ];
    };

    system.activationScripts.k3s-dirs = ''
      mkdir -p /var/lib/rancher/k3s/agent/etc/containerd
    '';

    systemd.services.k3s-network-taint-fix = lib.mkIf isServer {
      description = "Fix NetworkUnavailable taint";
      path = [ pkgs.kubectl ];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = pkgs.writeShellScript "fix-network-taint" ''
        export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
        for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
          kubectl patch node "$node" --type=merge \
            -p '{"status":{"conditions":[{"type":"NetworkUnavailable","status":"False","reason":"CNIIsUp","message":"CNI routes active"}]}}' \
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
