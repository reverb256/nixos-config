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
    # KUBERNETES API SERVER
    # ============================================================================
    services.kubernetes.apiserver = {
      enable = true;
      address = "https://10.1.1.110:6443";
      securePort = 6443;
    };

    # ============================================================================
    # KUBERNETES SCHEDULER
    # ============================================================================
    services.kubernetes.scheduler = {
      enable = true;
    };

    # ============================================================================
    # KUBERNETES CONTROLLER MANAGER
    # ============================================================================
    services.kubernetes.controllerManager = {
      enable = true;
    };

    # ============================================================================
    # KUBERNETES KUBELET
    # ============================================================================
    services.kubernetes.kubelet = {
      enable = true;
    };

    # ============================================================================
    # KUBERNETES PROXY
    # ============================================================================
    services.kubernetes.proxy = {
      enable = true;
    };

    # ============================================================================
    # FLANNEL CNI
    # ============================================================================
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
