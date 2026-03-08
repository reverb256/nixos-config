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
    # KUBERNETES CONTROL PLANE & WORKER
    # ============================================================================
    services.kubernetes = {
      enable = true;

      # Node roles
      roles = config.services.kubernetes-module.roles;

      # Master address (for workers to join)
      masterAddress = config.services.kubernetes-module.masterAddress;

      # API Server
      apiserver.enable = true;

      # etcd (key-value store)
      etcd.enable = true;

      # Scheduler
      scheduler.enable = true;

      # Controller Manager
      controllerManager.enable = true;

      # Kubelet
      kubelet.enable = true;

      # Proxy
      proxy.enable = true;

      # Flannel CNI
      flannel.enable = true;

      # EasyCerts for automatic TLS certificates
      easyCerts = true;

      # Cluster DNS domain
      dnsDomain = "cluster.local";

      # Pod network (Flannel VXLAN)
      podNets = ["10.244.0.0/16"];

      # Service network
      serviceNets = ["10.96.0.0/12"];

      # Kubernetes addons
      addons = {
        # CoreDNS for cluster DNS
        dns.enable = true;

        # Dashboard (disabled initially)
        dashboard.enable = false;
      };

      # RBAC and authorization
      rbac.enable = true;

      # Token-based authentication
      tokenAuth.enable = true;
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
