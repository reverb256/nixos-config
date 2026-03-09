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
        # Use CRI-O as container runtime (CRI v1 API compatible)
        containerRuntimeEndpoint = "unix:///run/crio/crio.sock";
      };
    };

    services.kubernetes.proxy = {
      enable = true;
    };

    services.kubernetes.flannel = {
      enable = true;
    };

    # ============================================================================
    # CRI-O CONTAINER RUNTIME (CRI v1 API compatible with Kubernetes 1.35.0)
    # ============================================================================
    virtualisation.cri-o = {
      enable = true;
      # Configure CNI to use /opt/cni/bin where Flannel plugin is located
      settings = {
        crio.network = {
          plugin_dirs = ["/opt/cni/bin"];
        };
      };
    };

    # ============================================================================
    # CNI CONFIGURATION - Flannel in proper .conflist format
    # ============================================================================
    # Create writable CNI directory for Flannel config and CDI spec
    systemd.tmpfiles.rules = [
      "d /var/lib/cni/net.d 0755 root root -"
      "L+ /var/lib/cni/net.d/10-flannel.conflist - - - - /etc/cni/flannel.conflist"
      "d /var/lib/cdi 0755 root root -"
    ];

    # Store the Flannel CNI config in a writable location
    environment.etc."cni/flannel.conflist".text = builtins.toJSON {
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
              ranges = [[{subnet = "10.244.0.0/16";}]];
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
    environment.etc."cni/net.d/10-crio-bridge.conflist".enable = lib.mkForce false;
    environment.etc."cni/net.d/99-loopback.conflist".enable = lib.mkForce false;

    # Configure kubelet to use the alternative CNI directory via environment
    systemd.services.kubelet.environment.CNI_CONF_DIR = "/var/lib/cni/net.d";
    systemd.services.kubelet.environment.CNI_BIN_DIR = "/opt/cni/bin";

    # NVIDIA Container Toolkit for GPU passthrough
    # Configure CRI-O to support GPU devices
    environment.etc."crio/crio.conf.d/10-gpu-devices.conf".text = ''
      [crio.runtime]
      # Pass through NVIDIA GPU devices to all containers
      # This is needed for the NVIDIA device plugin to detect GPUs
      device_ownership_from_security_context = false
      device_ownership = false
      # Use CDI for device passthrough
      cdi_spec_dirs = ["/var/lib/cdi"]
    '';

    # Write CDI spec via systemd service (CDI dir created by tmpfiles above)
    systemd.services.nvidia-cdi = {
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

    # Alternative: Use CDI for GPU devices (if nvidia-ctk works)
    # For now, we'll use the manifest-based approach with device mounts

    # ============================================================================
    # DOCKER (Optional - for non-Kubernetes container management)
    # NOTE: Not used by Kubernetes - CRI-O is the cluster container runtime
    # NOTE: NVIDIA GPU passthrough handled via nvidia-container-toolkit package
    # GPU devices are passed through directly by the kubelet/device plugin
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
    };

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
