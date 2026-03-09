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

    # Podman support
    ../../modules/services/podman-support.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "sentry";

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  hardware.profiles = {
    amd.zen = true;  # Zen CPU optimizations
    amdgpu.enable = true;  # AMD GPU support
    amdgpu.wayland = true;  # AMDGPU Wayland optimizations (ROC_ENABLE_PRE_VEGA)
    monitoring.enable = true;  # Hardware monitoring
  };

  # Hardware monitoring extras (not covered by profile)
  hardware.monitoring.autoDetect = true; # Auto-detect sensor chips
  hardware.monitoring.fanControl = false; # BIOS fan control for now

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  profiles.role = {
    mining = true;  # CPU mining only
    aiInference = true;  # AI inference gateway + MCP + RAG
  };

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  profiles.network.tailscale.enable = true;

  # ============================================================================
  # BOOTLOADER
  # ============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ============================================================================
  # KERNEL - Zen for better desktop responsiveness (matches other cluster hosts)
  # ============================================================================
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # Note: hardware.profiles.amdgpu.enable handles AMDGPU automatically

  services.xserver.videoDrivers = ["amdgpu"];

  # ============================================================================
  # ROCm SETUP (for AMD GPU monitoring)
  # ============================================================================
  # Note: hardware.profiles.amdgpu.wayland sets ROC_ENABLE_PRE_VEGA=1 automatically
  environment.variables = {
    LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
    OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
  };

  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
  ];

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
  # PLASMA WAYLAND
  # ============================================================================
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.defaultSession = "plasma";

  # ============================================================================
  # SECONDARY STORAGE (sda - 1TB SSD)
  # ============================================================================
  fileSystems."/storage" = {
    device = "/dev/disk/by-uuid/4cc9468d-166d-4479-9846-6224c80d9566";
    fsType = "btrfs";
    options = ["subvol=@data"];
  };

  # ============================================================================
  # MONITORING SERVER (Prometheus + Grafana)
  # Central metrics collection and visualization for the cluster
  # ============================================================================
  # TEMP: Disabled due to NixOS compatibility issues
  # services.monitoring.prometheus = {
  #   enable = true;
  #   retentionDays = 30;
  #   scrapeInterval = "15s";
  # };
  #
  # services.monitoring.grafana = {
  #   enable = true;
  #   domain = "sentry.ts.krogh.dev";
  # };

  # ============================================================================
  # MINING (CPU only - 8 threads = 50% of 16 cores)
  # Uses defaults from mining.nix for pool URLs and wallet format
  # ============================================================================
  # Note: profiles.role.mining enables services.mining automatically
  services.mining = {
    xmrig = {
      enable = true;
      autostart = true;
      threads = 8;
    };
    lolminer.enable = false;
  };

  # Spotify with SpotX patch (ad-free, premium features)
  services.spotify-spotx.enable = true;

  # ============================================================================
  # DISTRIBUTED BUILDS - DISABLED (local builds only)
  # ============================================================================
  nix.distributedBuilds = lib.mkForce false;
  # ============================================================================
  # NETWORKING
  # ============================================================================
  networking = {
    networkmanager = {
      enable = true;
      ensureProfiles.profiles."Wired connection 1" = {
        connection = {
          id = "Wired connection 1";
          type = "ethernet";
          interface-name = "enp7s0";
          autoconnect = true;
        };
        ipv4 = {
          method = "manual";
          address1 = "10.1.1.140/24";
          gateway = "10.1.1.1";
          dns = "127.0.0.1,::1";
        };
        ipv6.method = "auto";
      };
    };
  };

  # ============================================================================
  # TAILSCALE
  # ============================================================================
  services.tailscale.enable = true;

  # Mount /etc/nixos from zephyr (single-source-of-truth)
  services.nixos-share = {
    enable = true;
    client.enable = true;
  };

  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # ============================================================================
  # NIX-LD (For ROCm and mining software compatibility)
  # ============================================================================
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
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

  # ============================================================================
  # CI/CD
  # ============================================================================
  services.garnix.enable = false;
  services.nixos-auto-update.enable = true;

  # ============================================================================
  # GIT CONFIGURATION
  # ============================================================================
  programs.git = {
    enable = true;
    config = {
      user.name = "j_kro";
      user.email = "j_kro@sentry";
      init.defaultBranch = "main";
      remote.origin.url = "git@github.com:reverb256/nixos-config.git";
    };
  };

  # ============================================================================
  # HOME MANAGER - Centralized user configuration
  # ============================================================================
  imports = [
    ../../modules/system/home-manager.nix
  ];
}
