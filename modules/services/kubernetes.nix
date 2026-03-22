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
      default = [
        "master"
        "node"
      ];
      description = "Kubernetes roles for this node";
    };

    # etcd HA clustering options
    etcdInitialState = lib.mkOption {
      type = lib.types.enum [
        "new"
        "existing"
      ];
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

    apiserverBindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0"; # Bind to all interfaces so VIP (10.1.1.100) works
      example = "10.1.1.120";
      description = "API server bind address. Use 0.0.0.0 for VIP access, or specific IP for direct access only.";
    };

    etcdBootstrapOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "If true, this node starts etcd with only itself in initial-cluster (for bootstrap)";
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
        # Using default kubernetes from unstable (1.35.0)

        # Master address
        inherit (config.services.kubernetes-module) masterAddress;
        # PKI (Certificates) - Auto-generate with easyCerts
        easyCerts = true;
        # APIServer configuration
        apiserver = {
          serviceAccountSigningKeyFile = lib.mkForce "/etc/kubernetes/service-account-key.pem";
          serviceAccountKeyFile = lib.mkForce "/etc/kubernetes/service-account-key.pem";
          enable = isMaster;
          bindAddress = config.services.kubernetes-module.apiserverBindAddress;
          securePort = 6443;
          allowPrivileged = true;
          # Client certificates for authenticating to kubelet (logs, exec, port-forward)
          kubeletClientCertFile = "/var/lib/kubernetes/secrets/kube-apiserver-kubelet-client.pem";
          kubeletClientKeyFile = "/var/lib/kubernetes/secrets/kube-apiserver-kubelet-client-key.pem";
          extraOpts = "--api-audiences=api,https://kubernetes.default.svc,https://kubernetes.default.svc.cluster.local --endpoint-reconciler-type=none --encryption-provider-config=/etc/kubernetes/encryption-config.yaml --anonymous-auth=false";
          # HA Certificates: Include VIP and all control plane node IPs in SANs
          extraSANs = [
            # VIP for HA failover
            "10.1.1.100"
            # All control plane node IPs
            "10.1.1.110" # zephyr
            "10.1.1.120" # nexus
            "10.1.1.140" # sentry
            # Local hostname and cluster domain
            config.networking.hostName
            "${config.networking.hostName}.lan"
            "${config.networking.hostName}.cluster.local"
            "cluster.local"
            "kubernetes"
            "kubernetes.default"
            "kubernetes.default.svc"
            "kubernetes.default.svc.cluster.local"
          ];
          # Connect to local etcd (for multi-master HA, each node connects to its local etcd)
          etcd.servers = lib.mkForce ["http://${config.services.kubernetes-module.etcdListenHost}:2379"];
          # Note: Pod Security Admission is enabled by default in Kubernetes 1.25+
          # No extra configuration needed - uses built-in 'restricted' profile
        };
        scheduler.enable = isMaster;
        controllerManager = {
          enable = isMaster;
          # Migrated to 10.244.0.0/16 (Flannel default) to avoid overlap with host network (10.1.1.0/24)
          clusterCidr = lib.mkForce "10.244.0.0/16";
          extraOpts = "--allocate-node-cidrs=true";
        };
        kubelet = {
          enable = true;
          hostname = config.networking.hostName;
          clusterDns = ["10.0.0.10"]; # CoreDNS service IP
          # Client CA for verifying API server client certificates
          clientCaFile = "/var/lib/kubernetes/secrets/ca.pem";
          extraConfig = {
            failSwapOn = false;
            containerRuntimeEndpoint = "unix:///run/containerd/containerd.sock";
            # Kubelet authentication - require X509 client certificates from API server
            authentication = {
              anonymous = {
                enabled = false; # Disable anonymous access
              };
              x509 = {
                clientCAFile = "/var/lib/kubernetes/secrets/ca.pem";
              };
            };
            # Kubelet authorization - delegate to API server via webhook
            authorization = {
              mode = "Webhook";
              webhook = {
                cacheAuthorizedTTL = "5m0s";
                cacheUnauthorizedTTL = "30s";
              };
            };
          };
          # Node labels for GPU device plugin scheduling
          # NVIDIA device plugin requires: accelerator=nvidia-gpu
          # AMD device plugin requires: gpu=amd
          # Build conditional labels based on GPU types present on node
          extraOpts = let
            labels = lib.concatStringsSep "," (
              (lib.optional config.hardware.nvidia.enabled "accelerator=nvidia-gpu")
              ++ (lib.optional config.hardware.gpu-compute.rocm.enable "gpu=amd")
            );
          in
            lib.mkIf (labels != "") "--node-labels=${labels}";
        };
        proxy.enable = true;
        proxy.extraOpts = "--cluster-cidr=10.244.0.0/16";
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
        advertiseClientUrls = lib.mkForce [
          "http://${config.services.kubernetes-module.etcdListenHost}:2379"
        ];
        listenPeerUrls = lib.mkForce ["http://${config.services.kubernetes-module.etcdListenHost}:2380"];
        initialAdvertisePeerUrls = lib.mkForce [
          "http://${config.services.kubernetes-module.etcdListenHost}:2380"
        ];
        initialCluster = let
          clusterMembers =
            if useEtcdCluster
            then config.services.kubernetes-module.etcdClusterMembers
            else [
              "${config.services.kubernetes-module.masterAddress}=http://${config.services.kubernetes-module.masterAddress}:2380"
            ];
          # If bootstrapping, use only this node; otherwise use full cluster list
          effectiveMembers =
            if config.services.kubernetes-module.etcdBootstrapOnly
            then [
              "${config.services.kubernetes-module.etcdName}=http://${config.services.kubernetes-module.etcdListenHost}:2380"
            ]
            else clusterMembers;
        in
          lib.mkForce effectiveMembers;
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
        # Create etcd data directory with correct ownership (etcd user:group)
        "d /var/lib/etcd 0700 etcd etcd -"
        # Create writable containerd config directory for NVIDIA runtime
        "d /etc/containerd/conf.d 0755 root root -"
        # Create writable CNI directories (both for kubelet and containerd)
        "d /var/lib/cni/net.d 0755 root root -"
        # Create a writable /etc/cni/net.d by bind mounting from /var/lib/cni/net.d
        # This allows us to override the read-only /etc/static/cni/net.d
        # The bind mount is created in the activation script below
        # Kubelet reads from /var/lib/cni/net.d (configured via cniConfDir)
        "L+ /var/lib/cni/net.d/00-flannel.conflist - - - - /etc/cni/flannel.conflist"
        # Containerd reads from /etc/cni/net.d (default CNI path) - will be bind mounted
        "L+ /var/lib/cni/net.d/10-flannel.conflist - - - - /etc/cni/flannel.conflist"
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
      environment.etc."cni/flannel.conflist".text = builtins.toJSON {
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

          # Fix Flannel firewall rules for pod CIDR migration
          # Flannel creates FLANNEL-FWD chain with old CIDR (10.1.0.0/16)
          # This script updates it to use new CIDR (10.244.0.0/16)
          extraCommands = ''
            # Update FLANNEL-FWD chain for new pod CIDR
            if iptables -L FLANNEL-FWD -n &>/dev/null; then
              # Delete old rules with 10.1.0.0/16 CIDR
              iptables -D FLANNEL-FWD -s 10.1.0.0/16 -j ACCEPT 2>/dev/null || true
              iptables -D FLANNEL-FWD -d 10.1.0.0/16 -j ACCEPT 2>/dev/null || true
              # Add new rules with 10.244.0.0/16 CIDR
              iptables -C FLANNEL-FWD -s 10.244.0.0/16 -j ACCEPT 2>/dev/null || \
                iptables -I FLANNEL-FWD 1 -s 10.244.0.0/16 -j ACCEPT -m comment --comment "flanneld forward"
              iptables -C FLANNEL-FWD -d 10.244.0.0/16 -j ACCEPT 2>/dev/null || \
                iptables -I FLANNEL-FWD 2 -d 10.244.0.0/16 -j ACCEPT -m comment --comment "flanneld forward"
            fi
          '';
        } # Close worker config
      ]; # Close lib.mkMerge

      # ============================================================================
      # SYSTEMD SERVICE OVERRIDES - Control Plane Robustness
      # ============================================================================
      systemd.services = {
        # Setup NVIDIA containerd runtime configuration for GPU access
        nvidia-containerd-setup = lib.mkIf config.hardware.nvidia.enabled {
          description = "Setup NVIDIA containerd runtime configuration";
          before = ["containerd.service"];
          requiredBy = ["containerd.service"];
          path = [pkgs.util-linux pkgs.coreutils pkgs.nvidia-container-toolkit];
          serviceConfig.Type = "oneshot";
          script = ''
            # Create writable directory for containerd drop-in configs
            mkdir -p /etc/containerd/conf.d

            # Generate NVIDIA runtime configuration using nvidia-ctk
            # This creates /etc/containerd/conf.d/99-nvidia.toml with:
            # - nvidia runtime definition
            # - CDI enabled for GPU device passing
            ${pkgs.nvidia-container-toolkit}/bin/nvidia-ctk runtime configure \
              --runtime=containerd \
              --config=/etc/containerd/config.toml \
              --drop-in-config=/etc/containerd/conf.d/99-nvidia.toml \
              --nvidia-runtime-name=nvidia \
              --enable-cdi || echo "NVIDIA runtime configure failed, continuing..."
          '';
        };

        # Create bind mount for /etc/cni/net.d to override read-only Nix store
        # This allows containerd to use Flannel CNI instead of Cilium
        cni-net-setup = {
          description = "Setup CNI network configuration bind mount";
          before = ["containerd.service"];
          requiredBy = ["containerd.service"];
          path = [pkgs.util-linux pkgs.coreutils];
          serviceConfig.Type = "oneshot";
          script = ''
            # Create a writable directory for CNI configs
            mkdir -p /var/lib/cni/net.d

            # Copy flannel config if not exists
            if [ ! -f /var/lib/cni/net.d/10-flannel.conflist ]; then
              cp /etc/cni/flannel.conflist /var/lib/cni/net.d/10-flannel.conflist
            fi

            # Bind mount /etc/cni/net.d to the writable directory
            # This allows containerd to use our configs instead of the read-only store
            if ! mountpoint -q /etc/cni/net.d; then
              mount --bind /var/lib/cni/net.d /etc/cni/net.d
            fi
          '';
        };

        containerd = {
          after = lib.mkForce ["network.target"];
          before = ["kubelet.service"];
        };

        kubelet = {
          after = lib.mkForce [
            "containerd.service"
            "network.target"
          ];
          requires = lib.mkForce ["containerd.service"];
          serviceConfig = {
            ExecStartPre = pkgs.writeShellScript "wait-for-containerd" ''
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
            # Kubelet memory limits (applied to all nodes)
            MemoryMax = "2G";
            MemoryHigh = "1.5G";
            OOMScoreAdjust = -500;
          };
        };

        kube-apiserver = {
          after = lib.mkForce [
            "kubelet.service"
            "network.target"
          ];
          wants = lib.mkForce ["kubelet.service"];
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
            # ========================================================================
            # MEMORY PROTECTION - Prevent OOM kills of control plane
            # ========================================================================
            # API server typically uses 200-500MB. Set limits to prevent runaway.
            # Max 2GB is generous but prevents it from consuming all RAM.
            MemoryMax = "2G";
            MemoryHigh = "1.5G"; # Start soft limiting at 1.5GB
            # Negative OOM score = protects from OOM killer (-500 = highly protected)
            OOMScoreAdjust = -500;
          };
        };

        kube-scheduler = {
          after = lib.mkForce [
            "kube-apiserver.service"
            "network.target"
          ];
          requires = lib.mkForce ["kube-apiserver.service"];
          # Don't override ExecStart - let upstream handle it
          serviceConfig = {
            # Scheduler is lightweight (~100MB typical)
            MemoryMax = "512M";
            MemoryHigh = "256M";
            OOMScoreAdjust = -500;
          };
        };

        kube-controller-manager = {
          after = lib.mkForce [
            "kube-apiserver.service"
            "network.target"
          ];
          requires = lib.mkForce ["kube-apiserver.service"];
          # Don't override ExecStart - let upstream handle it
          serviceConfig = {
            # Controller manager uses ~200-400MB
            MemoryMax = "1G";
            MemoryHigh = "512M";
            OOMScoreAdjust = -500;
          };
        };

        # Generate Kubernetes encryption configuration with ROTATED key
        # SECURITY: Key is rotated due to previous key exposure in git history
        kubernetes-encryption-config = {
          description = "Create Kubernetes encryption configuration";
          wantedBy = [ "multi-user.target" ];
          before = [ "kube-apiserver.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "kubernetes-encryption-config" ''
              mkdir -p /etc/kubernetes
              cat > /etc/kubernetes/encryption-config.yaml <<'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
          - name: key1
            secret: ThYJ+8SNoXq6t+1hl+5osoApcBUi4odvzP852RHmvDs=
    - identity: {}  # fallback to identity for reading unencrypted secrets
EOF
              chmod 644 /etc/kubernetes/encryption-config.yaml
            '';
          };
        };
      }; # Close systemd.services

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
