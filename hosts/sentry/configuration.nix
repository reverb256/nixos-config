# Sentry Host Configuration - Monitoring Server
# 10.1.1.140 - 16 cores, RX 5600 XT
# Features: Gaming only (no VR), CPU mining, ROCm
#
# Module imports: Gaming, mining, monitoring, opencode are already imported
# via commonModules in flake.nix (./modules/default.nix)
# Gaming module is used here for Plasma desktop gaming optimizations
{lib, pkgs, ...}: {
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # All other modules (desktop, gaming, networking, services, etc.)
    ../../modules/default.nix

    # AMD GPU Wayland optimizations (includes nvtopPackages.full)
    ../../modules/hardware/amdgpu-wayland.nix

    # Podman support
    ../../modules/services/podman-support.nix

    # Kubernetes worker node (opt-in)
    ../../modules/services/kubernetes.nix
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
  networking.cluster-hosts = {
    enable = true;
    populateLocal = true;
  };

  # ============================================================================
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  # profiles.node.sentry-monitoring.enable = true;

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

    # Kubernetes worker configuration
    kubernetes-module = {
      enable = true;
      roles = ["node"];
      masterAddress = "10.1.1.110";
      # kubelet.hostname is automatically set from config.networking.hostName (clusterNetworking.hostName = "sentry")
    };

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

  # Kubernetes worker firewall rules
  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 10250 3100]; # SSH + Kubelet API + Loki (merges with cluster defaults)
  networking.firewall.allowedTCPPortRanges = lib.mkOptionDefault [
    {
      from = 30000;
      to = 32767;
    }
  ];
  networking.firewall.allowedUDPPorts = lib.mkOptionDefault [8472]; # Flannel VXLAN (merges with cluster defaults)
  # Open Loki port on main interface for cluster access (module only opens on tailscale0)
  networking.firewall.interfaces."enp7s0".allowedTCPPorts = [3100];

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
      xorg.libX11
      xorg.libXext
      xorg.libXrender
      xorg.libxcb
      xorg.libXau
      xorg.libXdmcp
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
}
