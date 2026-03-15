# Sentry Host Configuration - Monitoring Server
# 10.1.1.140 - 16 cores, RX 5600 XT
# Features: Gaming only (no VR), CPU mining, ROCm
#
# Module imports: Gaming, mining, monitoring, opencode are already imported
# via commonModules in flake.nix (./modules/default.nix)
# Gaming module is used here for Plasma desktop gaming optimizations
{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # All other modules (desktop, gaming, networking, services, etc.)
    ../../modules/default.nix

    # AMD GPU Wayland optimizations (includes nvtopPackages.full)
    ../../modules/hardware/amdgpu-wayland.nix
    ../../modules/hardware/rgb-control.nix

    # Podman support
    ../../modules/services/podman-support.nix

    # Kubernetes HA modules
    ../../modules/services/kubernetes.nix
    ../../modules/services/keepalived-vip.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  clusterNetworking = {
    enable = true;
    hostName = "sentry";
    ipAddress = "10.1.1.140";
    interfaceName = "enp7s0"; # Native hardware interface name
    wireless.enable = false; # Monitoring node - no WiFi needed
    unbound.listenAddress = "10.1.1.140"; # Listen on node IP for cluster DNS
  };

  # Populate /etc/hosts from central cluster configuration
  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };
    # Kubernetes worker firewall rules
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [22 10250 3100 3900 3901]; # SSH + Kubelet API + Loki + Garage (merges with cluster defaults)
      allowedTCPPortRanges = lib.mkOptionDefault [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [8472]; # Flannel VXLAN (merges with cluster defaults)
      # Open Loki port on main interface for cluster access (module only opens on tailscale0)
      interfaces."enp7s0".allowedTCPPorts = [3100];
    };
  };

  # ============================================================================
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  profiles.node.sentry-monitoring.enable = true;

  # ============================================================================
  # SERVICES - All service configurations
  # ============================================================================
  services = {
    # KUBERNETES HA - Control Plane Configuration
    # Override profile defaults: Sentry becomes a master node for HA
    kubernetes-module = {
      enable = true;
      # Override roles to include master
      roles = lib.mkForce ["master" "node"];
      # Use VIP (10.1.1.100) for HA control plane - certificates now include VIP and all node IPs in SANs
      masterAddress = lib.mkForce "10.1.1.100";
      # etcd clustering configuration (3-node HA cluster)
      etcdInitialState = "existing";
      etcdName = "sentry";
      etcdListenHost = "10.1.1.140";
      etcdClusterMembers = [
        "zephyr=http://10.1.1.110:2380"
        "nexus=http://10.1.1.120:2380"
        "sentry=http://10.1.1.140:2380"
      ];
    };

    # Keepalived VIP - priority 90 (lowest - backup master)
    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "enp7s0";
      priority = 90;
    };

    # Host Dashboard - Web interface for cluster host status
    host-dashboard = {
      enable = true;
      role = "control-plane + monitoring";
      port = 8090;
      prometheusUrl = "http://127.0.0.1:9090";
      featuredServices = [
        { name = "Prometheus"; url = "http://127.0.0.1:9090"; }
        { name = "Grafana"; url = "http://127.0.0.1:3000"; }
        { name = "Loki"; url = "http://127.0.0.1:3100"; }
      ];
      services = [
        { name = "kubelet"; active = true; }
        { name = "containerd"; active = true; }
        { name = "cfssl"; active = true; }
        { name = "keepalived"; active = true; }
        { name = "xmrig"; active = true; }
      ];
    };
  };

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  # Base profiles provided by node-profiles.sentry-monitoring:
  # - amd.zen, amdgpu.enable, amdgpu.wayland, monitoring.enable
  #
  # Sentry-specific hardware additions:
  hardware = {
    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = false; # Disabled: sensors-detect path issues
      fanControl = false; # BIOS fan control for now
    };

    # RGB control for AMD Wraith Prism cooler and MSI motherboard
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      wraithRgb.enable = true; # AMD Wraith Prism cooler
      temperatureReactive = {
        enable = true;
        sensor = "cpu"; # Monitor CPU temps
        thresholds = {
          cool = 45;
          warm = 60;
          hot = 70;
        };
        interval = 5;
      };
    };
  };

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  # Base role profiles provided by node-profiles.sentry-monitoring:
  # - mining, aiInference
  # Kubernetes and networking also handled by node profile
  #
  # No additional role profiles needed - all handled by node profile

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  # Base Tailscale configuration provided by node-profiles.sentry-monitoring
  # No additional network profile configuration needed

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================
  services = {
    # Crash detection and logging
    crash-watchdog.enable = true;

    # Compute Workload Monitor - Pause mining during builds/gaming
    compute-workload-monitor.enable = true;

    xserver.videoDrivers = ["amdgpu"];

    # MINING (CPU only - 8 threads = 50% of 16 cores)
    # Uses xmrig-proxy on Zephyr for centralized hashrate aggregation
    # Note: profiles.role.mining enables services.mining automatically
    # Sentry: RX 5600 XT available but not used for mining
    mining = {
      xmrig = {
        enable = true;
        autostart = true;
        threads = 8;
        pool = "10.1.1.110:3333"; # xmrig-proxy on Zephyr
        wallet = "sentry-cpu"; # Worker ID for proxy
        tls = false; # No TLS needed for local proxy
        httpTokenFile = "/run/agenix/xmrig-api-token"; # For HTTP API control
      };
      lolminer.enable = false; # No GPU mining on Sentry
    };

    # Spotify with SpotX patch (ad-free, premium features)
    spotify-spotx.enable = true;

    # TAILSCALE
    tailscale.enable = true;

    # Mount /etc/nixos from zephyr (single-source-of-truth)
    nixos-share = {
      enable = true;
      client.enable = true;
    };

    # NFS Client - Mount shared storage from nexus
    nfs-client = {
      enable = true;
      mountShared = true;
      mountHome = false;
      mountMedia = false;
    };

    # Syncthing P2P file sync for /etc/nixos config sync
    syncthing-cluster = {
      enable = true;
      deviceId = "SENTRY-PLACEHOLDER";
    };

    # Garage S3-compatible distributed object storage (3-node cluster)
    # Sentry hosts storage on local disk
    garage-cluster = {
      enable = true;
      dataDir = "/storage/garage"; # Local on sentry
      replicationFactor = 3;  # 3-node cluster
      consistencyMode = "consistent";  # Full consistency with 3 zones
      enableMetrics = true;  # Prometheus metrics on port 3903
      enableBackup = true;   # Daily metadata backups to NFS
      backupDir = "/data/shared/garage-backups";  # NFS from nexus
      rpcSecret = "b048d5cc40c1ccbdc9232c3830fbf0a47257c1f68b1debfadab4e6d93c38165a";
    };
  };

  # ============================================================================
  # BOOTLOADER CONFIGURATION
  # ============================================================================
  # Moved from hardware-configuration.nix for centralized config
  # Base bootloader settings provided by common-host-defaults.nix:
  # - systemd-boot.enable, efi.canTouchEfiVariables, kernelPackages (linux_zen)
  boot.loader.timeout = lib.mkDefault 5;

  # Environment configuration
  environment = {
    # ROCm SETUP (for AMD GPU monitoring)
    # Note: hardware.profiles.amdgpu.wayland sets ROC_ENABLE_PRE_VEGA=1 automatically
    variables = {
      LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
      OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
    };

    systemPackages = with pkgs; [
      rocmPackages.rocm-smi
      rocmPackages.rocminfo
    ];
  };

  systemd.tmpfiles.rules = let
    rocmEnv = pkgs.symlinkJoin {
      name = "rocm-combined";
      paths = with pkgs.rocmPackages; [
        clr
        clr.icd
        rocblas
        hipblas
        rpp
      ];
    };
  in [
    "L+ /opt/rocm - - - - ${rocmEnv}"
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];

  # ============================================================================
  # SECONDARY STORAGE (sda - 1TB SSD)
  # Defined in hardware-configuration.nix with subvol=@data
  # ============================================================================

  # Host-specific Tailscale override: Sentry advertises subnet routes (backup gateway)
  # This overrides the base Tailscale configuration from node profile
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  programs = {
    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [
      # AMD/ROCm libraries
      rocmPackages.clr
      rocmPackages.clr.icd
      rocmPackages.rocminfo
      rocmPackages.rocm-smi
      rocmPackages.rocm-runtime
      rocmPackages.rocblas
      rocmPackages.hipblas
      rocmPackages.hipsparse
      rocmPackages.rocfft
      rocmPackages.rocrand
      rocmPackages.rocthrust

      # OpenCL
      ocl-icd
      opencl-headers
      clinfo

      # System libraries
      zlib
      libpng
      libjpeg
      freetype
      fontconfig
      libx11
      libxext
      libxrender
      libxcb
      libxau
      libxdmcp
      SDL2
      alsa-lib
      systemd
      libusb1
      curl
      openssl
    ];

    # Git configuration now provided by common-host-defaults.nix
    # Sentry-specific git remote override (if needed):
    # programs.git.config.remote.origin.url = "git@github.com:reverb256/nixos-config.git";
  };

  # Agenix secrets for mining
  age = {
    identityPaths = ["/home/j_kro/.age/key.txt"];

    secrets.xmrig-api-token = {
      file = "${inputs.self}/secrets/xmrig-api-token.age";
      mode = "440";
      owner = "mining";
      group = "mining";
    };
  };
}
