# Nexus Host Configuration - Build and Backup Node
# 10.1.1.120 - 24 cores, 1x RTX 3060 Ti
# Features: Gaming + VR, MCP Servers
#
# Module imports: Gaming, mining, monitoring, opencode are already imported
# via commonModules in flake.nix (./modules/default.nix)
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

    # NVIDIA GPU Wayland support (host-dependent)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix
    ../../modules/hardware/rgb-control.nix

    # Desktop environment modules
    ../../modules/desktop/gamescope-tty.nix

    # Nexus-specific modules
    ../../modules/security/aistor-secrets.nix
    ../../modules/services/podman-support.nix

    # Kubernetes HA modules
    ../../modules/services/kubernetes.nix
    ../../modules/services/keepalived-vip.nix

    # Nix binary cache DISABLED
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  clusterNetworking = {
    enable = true;
    hostName = "nexus";
    ipAddress = "10.1.1.120";
    interfaceName = "enp7s0"; # Native hardware interface name
    wireless.enable = true; # Enable WiFi for versatility (interface: wlo1, native: wlp4s0)
    unbound.listenAddress = "10.1.1.120"; # Listen on node IP for cluster DNS
  };

  # Populate /etc/hosts from central cluster configuration
  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };

    # Nexus-specific firewall rules (in addition to cluster defaults)
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        10250 # Kubelet API
        3900  # Garage S3 API
        3901  # Garage RPC
      ];
      allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472 # Flannel VXLAN
      ];
    };
  };

  # ============================================================================
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  profiles.node.nexus-gaming.enable = true;

  # ============================================================================
  # SERVICES - All service configurations
  # ============================================================================
  services = {
    # KUBERNETES HA - Control Plane Configuration
    # Override profile defaults: Nexus becomes a master node for HA
    kubernetes-module = {
      enable = true;
      # Override roles to include master
      roles = lib.mkForce ["master" "node"];
      # Use VIP (10.1.1.100) for HA control plane - certificates now include VIP and all node IPs in SANs
      masterAddress = lib.mkForce "10.1.1.100";
      # etcd clustering configuration (3-node HA cluster)
      etcdInitialState = "existing";
      etcdName = "nexus";
      etcdListenHost = "10.1.1.120";
      etcdClusterMembers = [
        "zephyr=http://10.1.1.110:2380"
        "nexus=http://10.1.1.120:2380"
        "sentry=http://10.1.1.140:2380"
      ];
    };

    # Keepalived VIP - priority 100 (middle priority)
    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "enp7s0";
      priority = 100;
    };

    # Host Dashboard - Web interface for cluster host status
    host-dashboard = {
      enable = true;
      role = "control-plane + storage + gaming";
      port = 8090;
      prometheusUrl = "http://127.0.0.1:9090";
      featuredServices = [
        { name = "Prometheus"; url = "http://127.0.0.1:9090"; }
        { name = "Grafana"; url = "http://127.0.0.1:3000"; }
      ];
      services = [
        { name = "kubelet"; active = true; }
        { name = "containerd"; active = true; }
        { name = "cfssl"; active = true; }
        { name = "keepalived"; active = true; }
        { name = "NFS Server"; active = true; }
      ];
    };
  };

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  # Base profiles provided by node-profiles.nexus-gaming:
  # - amd.zen, nvidia.enable (single GPU), monitoring.enable
  #
  # Nexus-specific hardware additions:
  hardware = {
    # NVIDIA GPU support (base driver)
    nvidia-common.enable = true;

    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = true; # Auto-detect sensor chips
      fanControl = false; # BIOS fan control for now
    };

    # RGB control for Razer Naga Pro and Gigabyte motherboard
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      openrazer.enable = true; # Razer Naga Pro
      temperatureReactive = {
        enable = true;
        sensor = "cpu"; # Monitor CPU temps
        thresholds = {
          cool = 50;
          warm = 65;
          hot = 75;
        };
        interval = 5;
      };
    };
  };

  # ============================================================================
  # FILESYSTEM COMPRESSION - Enable zstd:3 on all BTRFS filesystems
  # ============================================================================
  fileSystems = {
    "/".options = lib.mkOptionDefault ["compress=zstd:3" "ssd" "discard=async"];
    "/home".options = lib.mkOptionDefault ["compress=zstd:3" "ssd" "discard=async"];
  };

  # ============================================================================
  # STORAGE CONFIGURATION
  # ============================================================================
  # Nexus has additional storage beyond the root filesystem:
  # - nvme1n1 (223.6GB) - "worn-storage" for high-write workloads
  # - bcache0 (3.6TB + 465GB cache) - "nexus-storage" with organized subvolumes

  fileSystems = {
    # Mount nexus-storage subvolumes (large bcache device)
    # Note: /data/worn is defined in hardware-configuration.nix
    "/data/home" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = ["subvol=home" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };

    "/data/shared" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = ["subvol=shared" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };

    "/data/backups" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = ["subvol=backups" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };

    "/data/media" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = ["subvol=media" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };

    "/var/lib/containers" = {
      device = "/dev/disk/by-uuid/08cbb21c-adb0-4e3c-928f-7b6d1fa2d236";
      fsType = "btrfs";
      options = ["subvol=containers" "compress=zstd" "ssd" "discard=async" "nofail" "x-systemd.device-timeout=10s"];
    };
  };

  # ============================================================================
  # BOOT CONFIGURATION
  # ============================================================================
  # Base bootloader settings provided by common-host-defaults.nix:
  # - systemd-boot.enable, efi.canTouchEfiVariables, kernelPackages (linux_zen)
  #
  # No Nexus-specific boot configuration needed

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  # Base role profiles provided by node-profiles.nexus-gaming:
  # - gaming, vr, mining, aiInference
  # Kubernetes and networking also handled by node profile
  #
  # No additional role profiles needed - all handled by node profile

  # Note: profiles.role.gaming enables services.gaming automatically

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  # Base Tailscale configuration provided by node-profiles.nexus-gaming
  # No additional network profile configuration needed

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================
  # Base Kubernetes configuration provided by node-profiles.nexus-gaming:
  # - worker role, masterAddress to zephyr
  #
  # Nexus-specific service additions:

  # Enable Steam Gamescope session alongside Plasma
  # Both sessions will be available in SDDM for selection
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  services = {
    # Compute workload monitor - pauses mining during builds
    compute-workload-monitor.enable = true;

    # Crash detection and logging
    crash-watchdog.enable = true;

    # Kubernetes worker configuration provided by node-profiles.nexus-gaming
    # No need to duplicate here

    garnix.enable = true;
    nixos-auto-update.enable = true;

    # Spotify with SpotX patch (ad-free, premium features)
    spotify-spotx.enable = true;

    # Mining configuration - CPU uses xmrig-proxy on Zephyr
    # Uses defaults from mining.nix for pool URLs and wallet format
    # Note: profiles.role.mining enables services.mining automatically
    mining = {
      # Dual XMRig setup (always-on + pause-able)
      # Total when idle: 12 threads (50%) - Total when gaming: 4 threads (17%)
      xmrigDual = {
        enable = true;
        # Always-on instance - mines even during gaming
        alwaysOn = {
          enable = true;
          threads = 4; # 17% of 24 cores
          httpPort = 8081;
          httpTokenFile = "/run/agenix/xmrig-always-api-token";
          autostart = true;
        };
        # Flexible instance - pauses during gaming/builds
        flexible = {
          enable = true;
          threads = 8; # 33% of 24 cores
          httpPort = 8082;
          httpTokenFile = "/run/agenix/xmrig-flexible-api-token";
          autostart = true;
        };
        # Common settings for both instances
        pool = "10.1.1.110:3333"; # xmrig-proxy on Zephyr
        wallet = "nexus-cpu"; # Worker ID for proxy
        password = "x";
        tls = false; # No TLS needed for local proxy
      };

      # GPU mining configuration - direct Kryptex connection
      # Multi-pool failover: US primary, EU fallback
      lolminer = {
        pools = [
          {
            url = "xtm-c29-us.kryptex.network:8040";  # Direct Kryptex US (primary)
            wallet = "krxXVNVMM7.nexus-gpu";
            password = "x";
            tls = true;  # TLS required for Kryptex
          }
          {
            url = "xtm-c29-eu.kryptex.network:8040";  # Direct Kryptex EU (fallback)
            wallet = "krxXVNVMM7.nexus-gpu";
            password = "x";
            tls = true;  # TLS required for Kryptex
          }
        ];
      };

      # NVIDIA GPU mining (RTX 3060 Ti @ 130W)
      lolminer.nvidia = {
        enable = true;
        autostart = true;
        devices = "0";
        powerLimit = 130; # 130W for optimal efficiency
        apiPort = 4068;
      };
    };

    # GPU Proxy - Stratum proxy for GPU miners (lolMiner)
    gpu-proxy = {
      enable = true;
      listenPort = 3334;
      apiPort = 8083;
      logLevel = "INFO";
      pools = [
        {
          name = "Kryptex US";
          url = "xtm-c29-us.kryptex.network:8040";
          wallet = "krxXVNVMM7";
          password = "x";
          priority = 1;
          tls = true;  # TLS required for port 8040
        }
        {
          name = "Kryptex EU";
          url = "xtm-c29-eu.kryptex.network:8040";
          wallet = "krxXVNVMM7";
          password = "x";
          priority = 2;
          tls = true;  # TLS required for port 8040
        }
      ];
      workers = [
        {
          id = "krxXVNVMM7.nexus-gpu";
          password = "x";
        }
        {
          id = "krxXVNVMM7.zephyr-gpu";
          password = "x";
        }
        {
          id = "krxXVNVMM7.forge-gpu";
          password = "x";
        }
      ];
      openFirewall = true;
    };

    # MCP servers
    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
    };

    # Mount /etc/nixos from zephyr (single-source-of-truth)
    nixos-share = {
      enable = true;
      client.enable = true;
    };

    # NFS Server - Export shared storage for cluster
    nfs.server.enable = true;

    # Syncthing P2P file sync for /etc/nixos config sync
    syncthing-cluster = {
      enable = true;
      deviceId = "NEXUS-PLACEHOLDER";
    };

    # Garage S3-compatible distributed object storage (3-node cluster)
    # Nexus hosts the primary storage on local bcache0
    garage-cluster = {
      enable = true;
      dataDir = "/data/shared/garage"; # Local on nexus (bcache0)
      replicationFactor = 3;  # 3-node cluster
      consistencyMode = "consistent";  # Full consistency with 3 zones
      enableMetrics = true;  # Prometheus metrics on port 3903
      enableBackup = false;  # Nexus IS the backup storage
      rpcSecret = "b048d5cc40c1ccbdc9232c3830fbf0a47257c1f68b1debfadab4e6d93c38165a";
    };
  };

  # ============================================================================
  # TAILSCALE (No route advertising - zephyr handles that)
  # ============================================================================
  # Host-specific override: Nexus does not advertise routes (zephyr handles that)
  # This overrides the base Tailscale configuration from node profile
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # ============================================================================
  # USER GROUPS
  # ============================================================================
  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "openrazer" "tailscale" "video" "render"];

  # ============================================================================
  # ADDITIONAL PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    opencode # AI coding agent (migrated from nix profile)
  ];

  # ============================================================================
  # NIX SETTINGS - Nexus-specific cache configuration
  # ============================================================================
  # Nexus uses common substituters from distributed-builds.nix
  # Note: Harmonia binary cache was removed (no local cache server running)
  # garnix.enable = true configures cache.garnix.io remote cache access
  nix.settings = {
    # No local substituters needed - using common caches from distributed-builds.nix
  };

  # ============================================================================
  # AGENIX SECRETS
  # ============================================================================
  # XMRig HTTP API tokens for dual-instance mining setup
  age = {
    identityPaths = ["/home/j_kro/.age/key.txt"];
    secrets = {
      # Always-on XMRig instance API token
      xmrig-always-api-token = {
        file = "${inputs.self}/secrets/xmrig-always-api-token.age";
        mode = "440";
        owner = "mining";
        group = "mining";
      };
      # Flexible XMRig instance API token (paused during gaming)
      xmrig-flexible-api-token = {
        file = "${inputs.self}/secrets/xmrig-flexible-api-token.age";
        mode = "440";
        owner = "mining";
        group = "mining";
      };
    };
  };

}
