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
  config,
  ...
}: {
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Common host imports (desktop, gaming, networking, etc.)
    ../../modules/common-host.nix

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
  # BOOTLOADER
  # ============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ============================================================================
  # KERNEL - Standard kernel for stability
  # ============================================================================
  boot.kernelPackages = pkgs.linuxPackages;

  # ============================================================================
  # GPU CONFIGURATION (AMD RX 5600 XT)
  # ============================================================================
  # Enable AMDGPU Wayland optimizations (includes nvtopPackages.full)
  hardware.amdgpu.wayland.enable = true;

  services.xserver.videoDrivers = ["amdgpu"];

  # Hardware monitoring (lm-sensors for CPU/motherboard temps)
  hardware.monitoring.enable = true;
  hardware.monitoring.autoDetect = true; # Auto-detect sensor chips
  hardware.monitoring.fanControl = false; # BIOS fan control for now

  # ============================================================================
  # ROCm SETUP (for AMD GPU monitoring)
  # ============================================================================
  environment.variables = {
    ROC_ENABLE_PRE_VEGA = "1";
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
  # MINING (CPU only - 8 threads = 50% of 16 cores)
  # Uses defaults from mining.nix for pool URLs and wallet format
  # ============================================================================
  services.mining = {
    enable = true;
    xmrig = {
      enable = true;
      threads = 8;
    };
    lolminer.enable = false;
  };

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
}
