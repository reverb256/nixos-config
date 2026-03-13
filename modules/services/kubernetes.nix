# Kubernetes Configuration Module
# Full upstream Kubernetes via services.kubernetes module
# Service Account Security
# Note: Service account tokens are NOT auto-mounted by default.
# Set automountServiceAccountToken: false in pod specs unless needed.
# See: docs/kubernetes/service-account-security.md
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
      default = "10.1.1.100";
      description = "IP address of the Kubernetes master node (or VIP for HA)";
    };

    roles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["master" "node"];
      description = "Kubernetes roles for this node";
    };

    # etcd HA clustering options
    etcdInitialState = lib.mkOption {
      type = lib.types.enum ["new" "existing"];
      default = "existing";
      description = "etcd initial cluster state: 'new' for first node, 'existing' for joining nodes";
    };

    etcdClusterMembers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [
        "zephyr=http://10.1.1.110:2380"
        "nexus=http://10.1.1.120:2380"
        "sentry=http://10.1.1.140:2380"
      ];
      description = "etcd cluster members in 'name=ip:port' format";
    };

    etcdName = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "etcd member name (typically hostname)";
    };

    etcdListenHost = lib.mkOption {
      type = lib.types.str;
      default = config.services.kubernetes-module.masterAddress;
      example = "10.1.1.140";
      description = "This node's IP address for etcd to listen on (must be actual IP, not VIP)";
    };
  };

  config = let
    isMaster = builtins.elem "master" config.services.kubernetes-module.roles;
    useEtcdCluster = config.services.kubernetes-module.etcdClusterMembers != [];
  in
    lib.mkIf config.services.kubernetes-module.enable {
      # ============================================================================
      # DISABLE PODMAN DOCKER COMPATIBILITY (conflicts with Docker)
      # CRI-O and Docker configuration
      # ============================================================================
      virtualisation = {
        podman = {
          dockerCompat = lib.mkForce false;
          dockerSocket.enable = lib.mkForce false;
        };
        # Switched to containerd for better NVIDIA GPU support
        # containerd is the Kubernetes default runtime since v1.24
        containerd = {
          enable = true;
        };
        cri-o = {
          enable = lib.mkForce false; # Disabled in favor of containerd
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
          # Note: Pod Security Admission is enabled by default in Kubernetes 1.25+
          # No extra configuration needed - uses built-in 'restricted' profile
        };
        scheduler.enable = isMaster;
        controllerManager = {
          enable = isMaster;
          # Cluster is using 10.1.0.0/16 for pod network (established, working)
          # TODO: Document migration plan to 10.244.0.0/16 for proper Flannel standard
          clusterCidr = lib.mkForce "10.1.0.0/16";
          extraOpts = "--allocate-node-cidrs=true";
        };
        kubelet = {
          enable = true;
          hostname = config.networking.hostName;
          clusterDns = ["10.0.0.10"];  # CoreDNS service IP
          extraConfig = {
            failSwapOn = false;
            containerRuntimeEndpoint = "unix:///run/containerd/containerd.sock";
          };
        };
        proxy.enable = true;
        # Flannel runs as DaemonSet in Kubernetes, not as systemd service
        # flannel.enable = true;  # Disabled: causes systemd symlink conflict
      };

      # ETCD (Required for Kubernetes control plane)
      # HA clustering support: use etcdClusterMembers list for multi-node setup
      services.etcd = lib.mkIf isMaster {
        enable = true;
        name = lib.mkForce config.services.kubernetes-module.etcdName;
        listenClientUrls = lib.mkForce [
          "http://127.0.0.1:2379"
          "http://${config.services.kubernetes-module.etcdListenHost}:2379"
        ];
        advertiseClientUrls = lib.mkForce ["http://${config.services.kubernetes-module.etcdListenHost}:2379"];
        listenPeerUrls = lib.mkForce ["http://${config.services.kubernetes-module.etcdListenHost}:2380"];
        initialAdvertisePeerUrls = lib.mkForce ["http://${config.services.kubernetes-module.etcdListenHost}:2380"];
        initialCluster = lib.mkForce (if useEtcdCluster then
          config.services.kubernetes-module.etcdClusterMembers
        else
          ["${config.services.kubernetes-module.masterAddress}=http://${config.services.kubernetes-module.masterAddress}:2380"]);
        initialClusterToken = "zephyr-etcd-cluster";
        initialClusterState = config.services.kubernetes-module.etcdInitialState;
      };

      # ============================================================================
      # CNI CONFIGURATION - Flannel in proper .conflist format
      # ============================================================================
      # Create writable CNI directory for Flannel config and CDI spec
      # Also create /var/lib/flannel for persistent subnet.env file (not on tmpfs)
      # Create symlink from /run/flannel to /var/lib/flannel for CNI plugin compatibility
      # Create local-path-provisioner directories for Kubernetes storage
      systemd.tmpfiles.rules = [
        # Create writable CNI directories (both for kubelet and containerd)
        "d /var/lib/cni/net.d 0755 root root -"
        # Remove /etc/cni/net.d if it exists as a symlink from old activation
        # Then create it as a writable directory for containerd's CNI config
        "r /etc/cni/net.d"
        "d /etc/cni/net.d 0755 root root -"
        # Create symlinks from read-only NixOS store to writable directories
        # Kubelet reads from /var/lib/cni/net.d (configured via cniConfDir)
        "L+ /var/lib/cni/net.d/10-flannel.conflist - - - - /etc/cni/flannel.conflist"
        # Containerd reads from /etc/cni/net.d (default CNI path)
        "L+ /etc/cni/net.d/10-flannel.conflist - - - - /etc/cni/flannel.conflist"
        # Removed CDI directory (containerd handles GPUs via nvidia-container-runtime)
        "d /var/lib/flannel 0755 root root -"
        "L+ /run/flannel - - - - /var/lib/flannel"
        # ============================================================================
        # LOCAL PATH PROVISIONER - Kubernetes local storage
        # ============================================================================
        # Default path for all nodes (Forge uses this)
        "d /var/local-path-provisioner 0777 root root -"
        # Zephyr: Fast NVMe storage for databases, AI models
        "d /data/k8s-local 0777 root root -"
        # Nexus: Large capacity on bcache0
        "d /data/containers/k8s-local 0777 root root -"
        # Sentry: HDD storage for archival, logs
        "d /storage/k8s-local 0777 root root -"
      ];

      # Store the Flannel CNI config
      # Use same format as working Zephyr control plane (cniVersion 0.3.1, name "cbr0")
      # The minimal delegate config lets Flannel handle bridge setup automatically
      environment.etc = {
        # Flannel CNI config (for kubelet via tmpfiles symlink)
        "cni/flannel.conflist".text = builtins.toJSON {
          name = "cbr0";
          cniVersion = "0.3.1";
          plugins = [
            {
              type = "flannel";
              delegate = {
                hairpinMode = true;
                isDefaultGateway = true;
              };
            }
            {
              type = "portmap";
              capabilities = {
                portMappings = true;
              };
            }
          ];
        };

        # Note: containerd's CNI config is provided via tmpfiles symlink above
        # (environment.etc."cni/net.d/..." doesn't work correctly for nested directories)

        # Disable CRI-O's default CNI configs (no longer needed with containerd)
        # "cni/net.d/10-crio-bridge.conflist".enable = lib.mkForce false;
        # "cni/net.d/99-loopback.conflist".enable = lib.mkForce false;

        # NVIDIA GPU device configuration (containerd uses nvidia-container-runtime directly)
        # No CRI-O-specific configuration needed
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
      # SYSTEMD SERVICE OVERRIDES - Control Plane Robustness
      # ============================================================================
      systemd.services.containerd = {
        after = lib.mkForce ["network.target"];
        before = ["kubelet.service"];
      };

      systemd.services.kubelet = {
        after = lib.mkForce ["containerd.service" "network.target"];
        requires = lib.mkForce ["containerd.service"];
        serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-containerd" ''
          echo "Waiting for containerd to be ready..."
          timeout=60
          while [ $timeout -gt 0 ]; do
            if ${pkgs.containerd}/bin/ctr version >/dev/null 2>&1; then
              echo "containerd is ready"
              exit 0
            fi
            sleep 1
            ((timeout--))
          done
          echo "ERROR: containerd not ready after 60 seconds"
          exit 1
        '';
      };

      systemd.services.kube-apiserver = {
        after = lib.mkForce ["kubelet.service" "network.target"];
        requires = lib.mkForce ["kubelet.service"];
        serviceConfig = {
          ExecStartPre = pkgs.writeShellScript "wait-for-kubelet" ''
            echo "Waiting for kubelet to be ready..."
            timeout=120
            while [ $timeout -gt 0 ]; do
              # Check if kubelet process is running and responding
              # kubelet serves healthz on http://localhost:10248/healthz
              # Note: kubelet doesn't need to be fully registered (API server connection)
              # Just needs to be running and healthy
              if ${pkgs.curl}/bin/curl -f -s http://localhost:10248/healthz >/dev/null 2>&1; then
                echo "Kubelet is ready (healthz responding)"
                exit 0
              fi
              # Also check if kubelet binary is running as fallback
              if pgrep -f "kubelet.*--hostname-override=zephyr" >/dev/null 2>&1; then
                echo "Kubelet is ready (process running)"
                exit 0
              fi
              sleep 2
              ((timeout--))
            done
            echo "ERROR: Kubelet not ready after 120 seconds"
            exit 1
          '';
          # Override upstream ExecStart - we want the actual service to run
          # ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
        };
      };

      systemd.services.kube-scheduler = {
        after = lib.mkForce ["kube-apiserver.service" "network.target"];
        requires = lib.mkForce ["kube-apiserver.service"];
        # Don't override ExecStart - let upstream handle it
      };

      systemd.services.kube-controller-manager = {
        after = lib.mkForce ["kube-apiserver.service" "network.target"];
        requires = lib.mkForce ["kube-apiserver.service"];
        # Don't override ExecStart - let upstream handle it
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
