{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.services.kubernetes;
  kubeUser = "kube";
  kubeGroup = "kube";
in {
  options.services.kubernetes = {
    enable = lib.mkEnableOption "Kubernetes services";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.kubectl;
      defaultText = lib.literalExample "pkgs.kubectl";
      description = "Kubernetes package to use.";
    };

    master = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Kubernetes master components (kubelet, apiserver, etc.).";
      };

      apiserver = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Kubernetes API server.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 6443;
          description = "Port for Kubernetes API server.";
        };

        advertiseAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Advertise address for Kubernetes API server.";
        };
      };

      controllerManager = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Kubernetes controller manager.";
        };
      };

      scheduler = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Kubernetes scheduler.";
        };
      };
    };

    worker = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Kubernetes worker components (kubelet, kube-proxy).";
      };

      kubelet = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Kubernetes kubelet.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 10250;
          description = "Port for Kubernetes kubelet.";
        };
      };

      kubeProxy = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable Kubernetes kube-proxy.";
        };
      };
    };

    containerRuntime = lib.mkOption {
      type = lib.types.enum ["docker" "containerd" "cri-o"];
      default = "containerd";
      description = "Container runtime for Kubernetes.";
    };

    clusterName = lib.mkOption {
      type = lib.types.str;
      default = "nixos-cluster";
      description = "Name of Kubernetes cluster.";
    };

    apiServerAddress = lib.mkOption {
      type = lib.types.str;
      default = "https://127.0.0.1:6443";
      description = "Address of the Kubernetes API server.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Auto-start the Kubernetes services.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create kube user and group
    users.users = lib.optionalAttrs (!lib.hasAttr "kube" config.users.users) {
      ${kubeUser} = {
        description = "Kubernetes user";
        isSystemUser = true;
        group = kubeGroup;
        extraGroups = ["docker" "podman"];
      };
    };

    users.groups = lib.optionalAttrs (!lib.hasAttr "kube" config.users.groups) {
      ${kubeGroup} = {};
    };

    # Install kubectl
    environment.systemPackages = with pkgs; [
      cfg.package
      kubernetes
      kubeadm
      kubelet
    ];

    # Enable container runtime based on selection
    virtualisation = lib.mkMerge [
      (lib.mkIf (cfg.containerRuntime == "docker") {
        docker = {
          enable = true;
          enableOnBoot = true;
        };
      })
      (lib.mkIf (cfg.containerRuntime == "containerd") {
        containerd = {
          enable = true;
        };
      })
      (lib.mkIf (cfg.containerRuntime == "cri-o") {
        cri-o = {
          enable = true;
        };
      })
    ];

    # Kubernetes master services
    systemd.services = lib.mkMerge [
      (lib.mkIf (cfg.master.enable && cfg.master.apiserver.enable) {
        kube-apiserver = {
          description = "Kubernetes API Server";
          after = ["network.target"];
          wantedBy = lib.optional cfg.autoStart ["multi-user.target"];

          serviceConfig = {
            Type = "simple";
            User = kubeUser;
            Group = kubeGroup;
            ExecStart = "${pkgs.kubernetes}/bin/kube-apiserver --secure-port=${toString cfg.master.apiserver.port} --advertise-address=${cfg.master.apiserver.advertiseAddress}";
            Restart = "always";
            RestartSec = 10;
          };
        };
      })

      (lib.mkIf (cfg.master.enable && cfg.master.controllerManager.enable) {
        kube-controller-manager = {
          description = "Kubernetes Controller Manager";
          after = ["network.target" "kube-apiserver.service"];
          wantedBy = lib.optional cfg.autoStart ["multi-user.target"];

          serviceConfig = {
            Type = "simple";
            User = kubeUser;
            Group = kubeGroup;
            ExecStart = "${pkgs.kubernetes}/bin/kube-controller-manager --master=${cfg.apiServerAddress}";
            Restart = "always";
            RestartSec = 10;
          };
        };
      })

      (lib.mkIf (cfg.master.enable && cfg.master.scheduler.enable) {
        kube-scheduler = {
          description = "Kubernetes Scheduler";
          after = ["network.target" "kube-apiserver.service"];
          wantedBy = lib.optional cfg.autoStart ["multi-user.target"];

          serviceConfig = {
            Type = "simple";
            User = kubeUser;
            Group = kubeGroup;
            ExecStart = "${pkgs.kubernetes}/bin/kube-scheduler --master=${cfg.apiServerAddress}";
            Restart = "always";
            RestartSec = 10;
          };
        };
      })

      (lib.mkIf (cfg.worker.enable && cfg.worker.kubelet.enable) {
        kubelet = {
          description = "Kubernetes Kubelet";
          after = ["network.target"];
          wantedBy = lib.optional cfg.autoStart ["multi-user.target"];

          serviceConfig = {
            Type = "simple";
            User = kubeUser;
            Group = kubeGroup;
            ExecStart = "${pkgs.kubelet}/bin/kubelet --container-runtime=${cfg.containerRuntime} --container-runtime-endpoint=unix:///run/${cfg.containerRuntime}/containerd.sock --port=${toString cfg.worker.kubelet.port}";
            Restart = "always";
            RestartSec = 10;
          };
        };
      })

      (lib.mkIf (cfg.worker.enable && cfg.worker.kubeProxy.enable) {
        kube-proxy = {
          description = "Kubernetes Proxy";
          after = ["network.target" "kubelet.service"];
          wantedBy = lib.optional cfg.autoStart ["multi-user.target"];

          serviceConfig = {
            Type = "simple";
            User = kubeUser;
            Group = kubeGroup;
            ExecStart = "${pkgs.kubernetes}/bin/kube-proxy --master=${cfg.apiServerAddress}";
            Restart = "always";
            RestartSec = 10;
          };
        };
      })
    ];

    # Enable required kernel modules for Kubernetes
    boot.kernelModules = ["br_netfilter" "ip_vs" "ip_vs_rr" "ip_vs_wrr" "ip_vs_sh"];
    boot.extraModprobeConfig = ''
      br_netfilter
      overlay
    '';
  };
}
