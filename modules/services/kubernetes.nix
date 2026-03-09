# Kubernetes Configuration Module
# Full upstream Kubernetes via services.kubernetes module
{ config, pkgs, lib, ... }:
{
  options.services.kubernetes-module = {
    enable = lib.mkEnableOption "Kubernetes cluster configuration";

    masterAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.1.1.110";
      description = "IP address of the Kubernetes master node";
    };

    roles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["master" "node"];
      description = "Kubernetes roles for this node";
    };
  };

  config = lib.mkIf config.services.kubernetes-module.enable {
    # ============================================================================
    # DISABLE PODMAN DOCKER COMPATIBILITY (conflicts with Docker)
    # ============================================================================
    virtualisation.podman.dockerCompat = lib.mkForce false;
    virtualisation.podman.dockerSocket.enable = lib.mkForce false;

    # ============================================================================
    # KUBERNETES MASTER ADDRESS
    # ============================================================================
    services.kubernetes.masterAddress = config.services.kubernetes-module.masterAddress;

    # ============================================================================
    # KUBERNETES PKI (Certificates) - Auto-generate with easyCerts
    # ============================================================================
    services.kubernetes.easyCerts = true;
    # Use module defaults for certificate paths
    services.kubernetes.apiserver.serviceAccountSigningKeyFile = lib.mkForce "/etc/kubernetes/service-account-key.pem";
    services.kubernetes.apiserver.serviceAccountKeyFile = lib.mkForce "/etc/kubernetes/service-account-key.pem";

    # ============================================================================
    # KUBERNETES APISERVER
    # ============================================================================
    services.kubernetes.apiserver = {
      enable = true;
      bindAddress = "10.1.1.110";
      securePort = 6443;
      # Allow privileged pods (needed for some system components)
      allowPrivileged = true;
    };

    # ============================================================================
    # ETCD (Required for Kubernetes control plane)
    # ============================================================================
    services.etcd = {
      enable = true;
      listenClientUrls = ["http://127.0.0.1:2379"];
      listenPeerUrls = ["http://10.1.1.110:2380"];
      initialAdvertisePeerUrls = ["http://10.1.1.110:2380"];
      initialCluster = ["10.1.1.110=http://10.1.1.110:2380"];
      initialClusterToken = "zephyr-etcd-cluster";
      initialClusterState = "new";
    };

    services.kubernetes.scheduler = {
      enable = true;
    };

    services.kubernetes.controllerManager = {
      enable = true;
    };

    services.kubernetes.kubelet = {
      enable = true;
      hostname = "zephyr";
      extraConfig = {
        # Fail on swap disabled for mining workstation
        failSwapOn = false;
        # Use containerd as container runtime
        containerd = "/run/containerd/containerd.sock";
      };
    };

    services.kubernetes.proxy = {
      enable = true;
    };

    services.kubernetes.flannel = {
      enable = true;
    };

    # ============================================================================
    # DOCKER (Required for Kubernetes)
    # ============================================================================
    virtualisation.docker = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };

    # ============================================================================
    # FIREWALL RULES
    # ============================================================================
    networking.firewall = {
      allowedTCPPorts = [
        6443   # Kubernetes API server
        2379   # etcd client
        2380   # etcd peer
        10250  # Kubelet API
        10251  # Kube-scheduler
        10252  # Kube-controller-manager
      ];

      allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];

      allowedUDPPorts = [8472];  # Flannel VXLAN
    };

    # ============================================================================
    # KUBERNETES TOOLS
    # ============================================================================
    environment.systemPackages = [ pkgs.kubernetes ];

    # kubectl aliases
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
  };
}
