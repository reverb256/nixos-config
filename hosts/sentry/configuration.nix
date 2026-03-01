# Sentry Host Configuration - Monitoring Server
# 10.1.1.140 - 16 cores, RX 5600 XT
# Features: Monitoring stack (Prometheus, Grafana), CPU mining, ROCm builds
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Common host imports (desktop, gaming, networking, etc.)
    ../../modules/common-host.nix

    # Host-specific GPU support
    ../../modules/hardware/amdgpu-wayland.nix
    ../../modules/services/podman-support.nix

    # ============================================================================
    # XNM1 MODULES - Essential tools for maintenance and monitoring
    # ============================================================================
    # Development (light - for monitoring tool development)
    ../../modules/development/tools.nix
    ../../modules/development/lsp.nix
    ../../modules/development/programming-languages.nix

    # Shell (XNM1 - for administration)
    ../../modules/development/fish-starship.nix

    # System (XNM1)
    ../../modules/system/distributed-builds.nix

    # Desktop Environment (XNM1 - for gaming)
    ../../modules/desktop/hyprland.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "sentry";

  # ============================================================================
  # MONITORING STACK - Exporters for sentry (central Prometheus on zephyr)
  # ============================================================================
  services.monitoring.node-exporter.enable = true;
  # Note: gpu-exporters module is NVIDIA-specific. AMD GPU metrics (amdgpu-exporter)
  # are not yet implemented as a module. Enable manually if needed.
  # services.gpu-exporters.enable = false;
  services.mining-exporter.enable = true; # XMRig metrics

  # ============================================================================
  # GAMING - Disabled on sentry
  # ============================================================================
  services.gaming = {
    enable = false;
    vr.enable = false;
  };

  # ============================================================================
  # KERNEL - Zen for better desktop responsiveness
  # ============================================================================
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # ============================================================================
  # GPU CONFIGURATION (AMD RX 5600 XT)
  # ============================================================================
  hardware.amdgpu.wayland = {
    enable = true;
    enable32Bit = true;
    opencl = false; # No GPU mining on Sentry
    sddmWayland = true;
  };

  services.xserver.videoDrivers = ["amdgpu"];

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
  # DISTRIBUTED BUILDS
  # ============================================================================
  nix.distributedBuilds = true;

  nix.settings = {
    substituters = lib.mkForce [
      "https://cache.nixos.org"
      "https://cache.nixos-cuda.org"
      "https://nix-community.cachix.org"
      "https://nixpkgs-wayland.cachix.org"
      "https://nix-gaming.cachix.org"
      "https://ezkea.cachix.org"
      "https://zen-browser.cachix.org"
      "https://devenv.cachix.org"
      "https://cache.garnix.io"
      "https://nixos-rocm.cachix.org"
    ];
    trusted-public-keys = lib.mkForce [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
      "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
      "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
      "zen-browser.cachix.org-1:z/QLGrEkiBYF/7zoHX1Hpuv0B26QrmbVBSy9yDD2tSs="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "nixos-rocm.cachix.org-1:VEpsf7pRIijjd8csKjFNBGzkBqOmw8H9PRmgAq14LnE="
    ];
  };

  # ============================================================================
  # NETWORKING
  # ============================================================================
  networking.interfaces.enp7s0.ipv4.addresses = [
    {
      address = "10.1.1.140";
      prefixLength = 24;
    }
  ];

  networking.defaultGateway = "10.1.1.1";

  # ============================================================================
  # TAILSCALE - Now managed by modules/system/tailscale.nix
  # ============================================================================
  # Tailscale routing automatically configured via network-constants

  # ============================================================================
  # WHISPER DICTATION - Disabled on sentry (no microphone/keyboard needs)
  # ============================================================================
  services.whisper-dictation.enable = false;

  # ============================================================================
  # OPENCODE - AI coding assistant - Disabled on sentry
  # ============================================================================
  services.opencode.enable = false;

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
  # BOOT SWITCH - Auto-deploy on boot
  # ============================================================================
  systemd.services.nixos-boot-switch = {
    description = "NixOS configuration switch on boot";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.writeScript "nixos-boot-switch" ''
        #!/bin/sh
        set -e
        cd /etc/nixos
        git fetch origin
        git checkout origin/infra || git checkout origin/main
        git reset --hard HEAD
        git pull origin $(git branch --show-current) 2>/dev/null || true
        exec nixos-rebuild switch --flake ".#sentry"
      ''}";
    };
  };
}
