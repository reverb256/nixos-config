# Kubernetes Configuration Module
# Full upstream Kubernetes via services.kubernetes module
{
  config,
  pkgs,
  lib,
  ...
}: {
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

  config = let
    isMaster = builtins.elem "master" config.services.kubernetes-module.roles;
    hasNvidiaGpu = config.hardware.profiles.nvidia.enable or false;
  in lib.mkIf config.services.kubernetes-module.enable {

    # ============================================================================
    # DISABLE PODMAN DOCKER COMPATIBILITY (conflicts with Docker)
    # CRI-O and Docker configuration
    # ============================================================================
    virtualisation = {
      podman = {
        dockerCompat = lib.mkForce false;
        dockerSocket.enable = lib.mkForce false;
      };
      cri-o = {
        enable = true;
        settings = {
          crio.network = {
            plugin_dirs = ["/opt/cni/bin"];
          };
        };
      };
      docker = {
        enable = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
        };
      };
    };

    # ============================================================================
    # KUBERNETES SERVICES - Consolidated configuration
    # ============================================================================
    services.kubernetes = {
      # Master address
      masterAddress = config.services.kubernetes-module.masterAddress;
      # PKI (Certificates) - Auto-generate with easyCerts
      easyCerts = true;
      # APIServer configuration
      apiserver = {
        serviceAccountSigningKeyFile = lib.mkForce "/etc/kubernetes/service-account-key.pem";
        serviceAccountKeyFile = lib.mkForce "/etc/kubernetes/service-account-key.pem";
        enable = isMaster;
        bindAddress = config.services.kubernetes-module.masterAddress;
        securePort = 6443;
        allowPrivileged = true;
      };
      scheduler.enable = isMaster;
      controllerManager.enable = isMaster;
      kubelet = {
        enable = true;
        hostname = config.networking.hostName;
        extraConfig = {
          failSwapOn = false;
          containerRuntimeEndpoint = "unix:///run/crio/crio.sock";
        };
      };
      proxy.enable = true;
      flannel.enable = true;
    };

    # ETCD (Required for Kubernetes control plane)
    services.etcd = {
      enable = isMaster;
      listenClientUrls = ["http://127.0.0.1:2379" "http://${config.services.kubernetes-module.masterAddress}:2379"];
      listenPeerUrls = ["http://${config.services.kubernetes-module.masterAddress}:2380"];
      initialAdvertisePeerUrls = ["http://${config.services.kubernetes-module.masterAddress}:2380"];
      initialCluster = ["${config.services.kubernetes-module.masterAddress}=http://${config.services.kubernetes-module.masterAddress}:2380"];
      initialClusterToken = "zephyr-etcd-cluster";
      initialClusterState = "new";
    };

    # ============================================================================
    # CNI CONFIGURATION - Flannel in proper .conflist format
    # ============================================================================
    # Create writable CNI directory for Flannel config and CDI spec
    # Also create /var/lib/flannel for persistent subnet.env file (not on tmpfs)
    # Create symlink from /run/flannel to /var/lib/flannel for CNI plugin compatibility
    systemd = {
      tmpfiles.rules = [
        "d /var/lib/cni/net.d 0755 root root -"
        "L+ /var/lib/cni/net.d/10-flannel.conflist - - - - /etc/cni/flannel.conflist"
        "d /var/lib/cdi 0755 root root -"
        "d /var/lib/flannel 0755 root root -"
        "L+ /run/flannel - - - - /var/lib/flannel"
      ];

      services = {
        # Configure kubelet to use the alternative CNI directory
        kubelet.environment = {
          CNI_CONF_DIR = "/var/lib/cni/net.d";
          CNI_BIN_DIR = "/opt/cni/bin";
        };

        # NVIDIA CDI spec service (for worker nodes with NVIDIA GPUs)
        nvidia-cdi = lib.mkIf (hasNvidiaGpu && !isMaster) {
      description = "NVIDIA GPU CDI Specification";
      wantedBy = ["multi-user.target"];
      before = ["crio.service"];
      serviceConfig.Type = "oneshot";
      script = ''
            mkdir -p /var/lib/cdi
            cat > /var/lib/cdi/nvidia-gpu.yaml <<'EOF'
        cdiVersion: "0.3.0"
        kind: nvidia.com/gpu
        devices:
        - containerEdits:
          - env:
            - name: NVIDIA_VISIBLE_DEVICES
              value: all
            - name: NVIDIA_DRIVER_CAPABILITIES
              value: compute,utility
          - deviceNodes:
            - hostPath: /dev/nvidia0
              permissions: rwm
            - hostPath: /dev/nvidia1
              permissions: rwm
            - hostPath: /dev/nvidiactl
              permissions: rwm
            - hostPath: /dev/nvidia-modeset
              permissions: rwm
            - hostPath: /dev/nvidia-uvm
              permissions: rwm
            - hostPath: /dev/nvidia-uvm-tools
              permissions: rwm
            - hostPath: /dev/nvidia-caps
              permissions: rwm
          - mounts:
            - hostPath: /run/opengl-driver/lib
              containerPath: /run/opengl-driver/lib
            - hostPath: /run/opengl-driver/lib64
              containerPath: /run/opengl-driver/lib64
            - hostPath: /run/opengl-driver
              containerPath: /run/opengl-driver
          name: all
        EOF
      '';
        };
      };
    };

    # Store the Flannel CNI config and configure CRI-O's CNI
    environment.etc = {
      # Flannel CNI config
      "cni/flannel.conflist".text = builtins.toJSON {
        cniVersion = "1.0.0";
        name = "mynet";
        plugins = [
          {
            type = "flannel";
            delegate = {
              type = "bridge";
              bridge = "mynet";
              isDefaultGateway = true;
              hairpinMode = true;
              ipam = {
                type = "host-local";
                ranges = [[{subnet = "10.1.0.0/16";}]];
              };
            };
          }
          {
            type = "portmap";
            capabilities = {portMappings = true;};
          }
        ];
      };

      # Disable CRI-O's default CNI configs
      "cni/net.d/10-crio-bridge.conflist".enable = lib.mkForce false;
      "cni/net.d/99-loopback.conflist".enable = lib.mkForce false;

      # NVIDIA GPU device configuration for CRI-O
      "crio/crio.conf.d/10-gpu-devices.conf".text = ''
        [crio.runtime]
        # Pass through NVIDIA GPU devices to all containers
        device_ownership_from_security_context = false
        device_ownership = false
        # Use CDI for device passthrough
        cdi_spec_dirs = ["/var/lib/cdi"]
      '';
    };

    # ============================================================================
    # FIREWALL RULES
    # ============================================================================
    networking.firewall = lib.mkMerge [
      # Master node firewall
      (lib.mkIf isMaster {
        allowedTCPPorts = [
          6443 # Kubernetes API server
          2379 # etcd client
          2380 # etcd peer
          10250 # Kubelet API
          10251 # Kube-scheduler
          10252 # Kube-controller-manager
        ];

        allowedTCPPortRanges = [
          {
            from = 30000;
            to = 32767;
          }
        ];

        allowedUDPPorts = [8472]; # Flannel VXLAN
      })

      # Worker node firewall (applies to all nodes, but ports differ per role)
      {
        allowedTCPPorts = lib.mkIf (!isMaster) [10250]; # Kubelet API only for workers
        allowedTCPPortRanges = [
          {
            from = 30000;
            to = 32767;
          }
        ];
        allowedUDPPorts = [8472]; # Flannel VXLAN
      }
    ];

    # ============================================================================
    # KUBERNETES TOOLS
    # ============================================================================
    environment.systemPackages = with pkgs; [
      kubernetes
      nvidia-container-toolkit
      cri-tools # crictl for CRI debugging
    ];

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
