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

    # Calico BGP configuration
    calicoBgp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Calico BGP for dynamic pod route advertisement between nodes";
      };

      asNumber = lib.mkOption {
        type = lib.types.int;
        default = 64512;
        description = "BGP AS number (64512-65534 are private use range)";
      };

      nodeToNodeMeshEnabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable full mesh BGP peerings between all nodes";
      };

      logSeverityScreen = lib.mkOption {
        type = lib.types.str;
        default = "Info";
        description = "Calico BGP log severity level (Debug, Info, Warning, Error)";
      };

      serviceClusterIPs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["10.96.0.0/12"];
        description = "ClusterIP CIDRs to advertise via BGP";
      };

      serviceLoadBalancerIPs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "LoadBalancer IP ranges to advertise via BGP (empty = all)";
      };

      serviceExternalIPs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "External IP ranges to advertise via BGP (empty = all)";
      };
    };

    # Calico IPVS configuration
    calicoIpvs = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable IPVS (IP Virtual Server) for more efficient Kubernetes service load balancing";
      };

      autoHostRanges = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically manage host address ranges for NAT";
      };

      strictArp = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable strict ARP mode for kube-proxy compatibility";
      };
    };

    # Calico WireGuard configuration
    calicoWireguard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable WireGuard encryption for inter-node pod traffic";
      };

      listeningPort = lib.mkOption {
        type = lib.types.port;
        default = 51820;
        description = "UDP port for WireGuard listening (default: 51820)";
      };

      routingRulePriority = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "WireGuard routing rule priority (higher = more preferred)";
      };

      interfaceName = lib.mkOption {
        type = lib.types.str;
        default = "wireguard.cali";
        description = "WireGuard interface name";
      };
    };
  };

  config = let
    isMaster = builtins.elem "master" config.services.kubernetes-module.roles;
    useEtcdCluster = config.services.kubernetes-module.etcdClusterMembers != [];

    # ============================================================================
    # CALICO CNI OFFICIAL BINARIES - Hybrid Declarative Fix
    # ============================================================================
    # NixOS calico-cni-plugin package is incomplete (missing calico-ipam binary)
    # This derivation provides official Calico v3.28.0 CNI binaries from upstream
    # Issue: https://github.com/projectcalico/calico/issues/XXXX
    # Solution: Extract binaries from official release tarball
    calico-official = pkgs.stdenv.mkDerivation rec {
      pname = "calico-cni-official";
      version = "3.28.0";

      # Official Calico release bundle containing all CNI binaries
      src = pkgs.fetchurl {
        url = "https://github.com/projectcalico/calico/releases/download/v${version}/release-v${version}.tgz";
        sha256 = "1ac9qh8f5am3akj37x9ypx51sj4hmz8ahzdblfpjyc40yxgr86qa";
      };

      # The binaries are in release-v3.28.0/bin/cni/amd64/
      sourceRoot = "release-v${version}";

      installPhase = ''
        mkdir -p $out/bin
        # Install Calico CNI binaries (amd64)
        cp bin/cni/amd64/calico $out/bin/
        cp bin/cni/amd64/calico-ipam $out/bin/
        chmod +x $out/bin/*
      '';
    };
  in
    lib.mkIf config.services.kubernetes-module.enable {
      # Assertions for BGP and IPVS configuration validation
      assertions = [
        {
          assertion = config.services.kubernetes-module.calicoBgp.enable -> (config.services.kubernetes-module.calicoBgp.asNumber >= 64512 && config.services.kubernetes-module.calicoBgp.asNumber <= 65534);
          message = "BGP AS number must be in private range 64512-65534 (got ${toString config.services.kubernetes-module.calicoBgp.asNumber})";
        }
        {
          assertion = config.services.kubernetes-module.calicoBgp.enable -> builtins.match "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]+$" (builtins.head config.services.kubernetes-module.calicoBgp.serviceClusterIPs) != null;
          message = "BGP serviceClusterIPs must be valid CIDR notation (e.g., 10.96.0.0/12)";
        }
      ];

      # Load IPVS kernel modules if enabled
      boot.kernelModules = lib.mkIf config.services.kubernetes-module.calicoIpvs.enable [
        "ip_vs"           # IPVS core module
        "ip_vs_rr"        # Round-robin scheduling
        "ip_vs_wrr"       # Weighted round-robin scheduling
        "ip_vs_sh"        # Source hashing scheduling
        "nf_conntrack"    # Connection tracking (already loaded by default)
      ];

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
          # Match Calico IPPool (10.244.0.0/16)
          clusterCidr = lib.mkForce "10.244.0.0/16";
          extraOpts = "--allocate-node-cidrs=true";
        };
        kubelet = {
          enable = true;
          hostname = config.networking.hostName;
          clusterDns = ["10.0.0.10"]; # CoreDNS service IP
          # CNI packages for Calico
          # cni-plugins: Standard CNI plugins (bridge, vlan, etc.)
          # calico-official: Official Calico CNI binaries with calico-ipam (fixes missing binary)
          cni.packages = with pkgs; [ cni-plugins calico-official ];
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
        # Configure kube-proxy mode: iptables (default) or ipvs (better performance)
        proxy.extraOpts = lib.mkMerge [
          # Default: iptables mode
          (lib.mkIf (!config.services.kubernetes-module.calicoIpvs.enable) "--cluster-cidr=10.244.0.0/16")
          # IPVS mode: O(1) lookup vs O(n) iptables, better for high-service-count clusters
          (lib.mkIf config.services.kubernetes-module.calicoIpvs.enable (
            lib.concatStringsSep " " [
              "--cluster-cidr=10.244.0.0/16"
              "--proxy-mode=ipvs"
              "--ipvs-scheduler=rr"  # Round-robin scheduling
              "--ipvs-min-sync-period=1s"
              "--ipvs-sync-period=10s"
              "--ipvs-strict-arp=true"  # Enable strict ARP for kube-proxy compatibility
            ]
          ))
        ];
        # Calico runs as DaemonSet in Kubernetes, not as systemd service
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
      # CNI CONFIGURATION - Calico
      # ============================================================================
      # Create writable CNI directories for Calico
      # Calico CNI plugin (installed via DaemonSet) manages /etc/cni/net.d
      # Create local-path-provisioner directories for Kubernetes storage
      systemd.tmpfiles.rules = [
        # Create etcd data directory with correct ownership (etcd user:group)
        "d /var/lib/etcd 0700 etcd etcd -"
        # Create writable containerd config directory for NVIDIA runtime
        "d /etc/containerd/conf.d 0755 root root -"
        # Create writable CNI directories (both for kubelet and containerd)
        "d /var/lib/cni/net.d 0755 root root -"
        # ============================================================================
        # CALICO CNI PLUGINS - Persistent symlinks to official Calico binaries
        # ============================================================================
        # Calico CNI plugin binaries from calico-official package
        # These symlinks persist across NixOS activations (unlike systemd service)
        "L+ /opt/cni/bin/calico - - - - ${calico-official}/bin/calico"
        "L+ /opt/cni/bin/calico-ipam - - - - ${calico-official}/bin/calico-ipam"
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

      # Note: Calico CNI config is managed by Calico DaemonSet
      # Calico writes to /etc/cni/net.d/10-calico.conflist dynamically
      # Kubelet reads from /var/lib/cni/net.d (configured via cniConfDir)
      # Calico's install-cni container copies config to both locations

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
            179 # Calico BGP
            5473 # Calico Typha
          ];

          allowedTCPPortRanges = [
            {
              from = 30000;
              to = 32767;
            }
          ];

          allowedUDPPorts = lib.mkOptionDefault (
            [8472 4789] ++ lib.optional config.services.kubernetes-module.calicoWireguard.enable
              config.services.kubernetes-module.calicoWireguard.listeningPort
          );
        })

        # Worker node firewall (applies to all nodes, but ports differ per role)
        {
          allowedTCPPorts = lib.mkIf (!isMaster) [10250 179 5473]; # Kubelet API + BGP + Typha for workers
          allowedTCPPortRanges = [
            {
              from = 30000;
              to = 32767;
            }
          ];
          allowedUDPPorts = lib.mkOptionDefault (
            [8472 4789] ++ lib.optional config.services.kubernetes-module.calicoWireguard.enable
              config.services.kubernetes-module.calicoWireguard.listeningPort
          );
        } # Close worker config
      ]; # Close lib.mkMerge

      # ============================================================================
      # SYSTEMD SERVICE OVERRIDES - Control Plane Robustness
      # ============================================================================
      systemd.services = {
        # Add IPVS tools to kube-proxy PATH
        kube-proxy = lib.mkIf config.services.kubernetes-module.calicoIpvs.enable {
          serviceConfig.Environment = lib.mkForce [
            "PATH=${lib.makeBinPath (with pkgs; [iptables conntrack-tools coreutils findutils gnugrep gnused systemd ipset kmod])}"
          ];
        };

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

        # Setup Calico CNI plugin symlinks
        # NixOS manages /opt/cni/bin as symlinks to cni-plugins package
        # We add Calico CNI plugins by creating additional symlinks to the calico-cni-plugin package
        calico-cni-setup = {
          description = "Setup Calico CNI plugin symlinks";
          before = ["containerd.service"];
          requiredBy = ["containerd.service"];
          path = [pkgs.util-linux pkgs.coreutils];
          serviceConfig.Type = "oneshot";
          script = ''
            # Ensure /opt/cni/bin exists
            mkdir -p /opt/cni/bin

            # Create symlinks to Calico CNI binaries from calico-official package
            # Calico CNI plugin provides: calico, calico-ipam (separate binaries in v3.28.0)
            calico_bin="${calico-official}/bin/calico"
            calico_ipam_bin="${calico-official}/bin/calico-ipam"

            # Create symlink for calico CNI plugin
            if [ ! -L /opt/cni/bin/calico ]; then
              ln -sf "$calico_bin" /opt/cni/bin/calico
            fi

            # Create symlink for calico-ipam (separate binary in official release)
            if [ ! -L /opt/cni/bin/calico-ipam ]; then
              ln -sf "$calico_ipam_bin" /opt/cni/bin/calico-ipam
            fi

            echo "Calico CNI plugins installed at /opt/cni/bin/"
            ls -la /opt/cni/bin/calico*
          '';
        };

        # Setup CNI network configuration for Calico
        # Calico DaemonSet's install-cni container writes to /etc/cni/net.d
        # We need to ensure the directory exists and is writable
        cni-net-setup = {
          description = "Setup CNI network configuration for Calico";
          before = ["containerd.service"];
          requiredBy = ["containerd.service"];
          path = [pkgs.util-linux pkgs.coreutils];
          serviceConfig.Type = "oneshot";
          script = ''
            # Create a writable directory for CNI configs
            mkdir -p /var/lib/cni/net.d

            # Ensure /etc/cni/net.d exists and is writable
            # Calico's install-cni container will write 10-calico.conflist here
            mkdir -p /etc/cni/net.d

            # Remove any old Flannel configs
            rm -f /var/lib/cni/net.d/*-flannel.conflist
            rm -f /etc/cni/net.d/*-flannel.conflist

            echo "CNI directories ready for Calico configuration"
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

        # CRITICAL: etcd OOM protection via systemd override
        # etcd is the cluster state database - must never be OOM killed
        etcd = lib.mkIf isMaster {
          serviceConfig = {
            OOMScoreAdjust = -1000;  # Maximum protection - never kill etcd
            MemoryMax = "2G";
            MemoryHigh = "1G";
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
      ] ++ lib.optionals config.services.kubernetes-module.calicoIpvs.enable [
        ipvsadm    # IPVS administration tool
        ipset      # IPset management for IPVS
        kmod       # modprobe for kernel module management
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
