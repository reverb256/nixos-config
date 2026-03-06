# Sentry Host Configuration - Monitoring Server
# 10.1.1.140 - 16 cores, RX 5600 XT
# Features: Gaming only (no VR), CPU mining, ROCm
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

    # Gaming support
    ../../modules/gaming/gaming.nix

    # Mining support
    ../../modules/mining/mining.nix

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
