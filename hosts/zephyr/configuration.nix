# Zephyr Host Configuration - Master Workstation
# 10.1.1.110 - 32 cores, RTX 3090
# Features: Gaming + VR, Stability Matrix, Nix Cache Server, MCP Servers
{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Common host imports (desktop, gaming, networking, etc.)
    ../../modules/common-host.nix

    # NVIDIA GPU support (common enables wayland module)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix

    # Alternative desktop environments
    ../../modules/desktop/hyprland.nix
    ../../modules/desktop/niri.nix
    ../../modules/desktop/sway.nix

    # Visual theming (Stylix + Base24)
    ../../modules/desktop/stylix-base24.nix

    # Zephyr-specific modules
    ../../modules/services/stability-matrix.nix
    ../../modules/services/llama-server.nix
    ../../modules/system/nix-cache-server.nix
    ../../modules/services/mcp-servers.nix
    ../../modules/services/github-actions-runner.nix
    ../../modules/security/aistor-secrets.nix
    ../../modules/services/hoyoverse-controller-fix.nix
    ../../modules/services/whisper-dictation.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "zephyr";

  # ============================================================================
  # VISUAL THEMING (Stylix)
  # ============================================================================
  stylix.enable = true;
  # stylix.image = /etc/nixos/wallpapers/zephyr.png;  # TODO: Add wallpaper

  # ============================================================================
  # ALTERNATIVE DESKTOP ENVIRONMENT (Hyprland)
  # ============================================================================
  programs.hyprland.enable = true;

  # Display Manager - Plasma Login Manager (NEW in Plasma 6.6)
  # Replaces SDDM with better multi-monitor, HDR, and systemd integration
  services.displayManager.plasma-login-manager.enable = true;
  services.displayManager.autoLogin.user = "j_kro";

  # Multi-GPU: Tell KWin to use RTX 3090 (card1) for display
  # RTX 3060 Ti (card0) has no monitors - used for compute only
  hardware.nvidia.wayland.multiGpu = {
    enable = true;
    primaryCard = "/dev/dri/card1";
  };

  # ============================================================================
  # GAMING + VR (Full support - RTX 3090)
  # ============================================================================
  services.gaming = {
    enable = true;
    vr.enable = true; # WiVRn, SteamVR, OpenXR
  };

  # HoYoverse controller fix (DualSense/DualShock)
  services.hoyoverse-controller-fix.enable = true;

  # ============================================================================
  # STABILITY MATRIX - Stable Diffusion Package Manager
  # ============================================================================
  programs.stability-matrix = {
    enable = true;
    enableCuda = true;
    dataDir = "/home/j_kro/.stabilitymatrix";
  };

  # ============================================================================
  # MINING MONITOR PLASMOID
  # ============================================================================
  programs.mining-plasmoid.enable = true;

  # ============================================================================
  # LOCALSEND - Cross-platform file sharing
  # ============================================================================
  programs.localsend = {
    enable = true;
    openFirewall = true;
  };

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
          interface-name = "enp38s0";
          autoconnect = true;
        };
        ipv4 = {
          method = "manual";
          address1 = "10.1.1.110/24";
          gateway = "10.1.1.1";
          dns = "127.0.0.1,::1";
        };
        ipv6.method = "auto";
      };
    };

    firewall = {
      allowedTCPPorts = [9757 18789 18790];
      allowedUDPPorts = [9757 9758 9759 27031 27036 5353 9947];
      interfaces."tailscale0".allowedTCPPorts = [18789 18790];
    };
  };

  # ============================================================================
  # KERNEL - CachyOS x86_64-v3 for gaming (Zen 3 architecture)
  # ============================================================================
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # ============================================================================
  # SERVICES
  # ============================================================================
  services = {
    garnix.enable = true;
    nixos-auto-update.enable = true;

    # Mining DISABLED - start manually with: systemctl start mining.slice
    # mining = {
    #   enable = true;
    #   xmrig = {
    #     enable = true;
    #     threads = 16;
    #   };
    #   lolminer = {
    #     enable = true;
    #     nvidia = {
    #       enable = true;
    #       devices = "0";
    #       powerLimit = 250;
    #     };
    #   };
    # };

    tailscale.enable = true;

    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
    };

    nix-cache-server = {
      enable = true;
      port = 8080;
    };

    # Whisper Dictation - Speech-to-text with KDE integration
    whisper-dictation = {
      enable = true;
      model = "base.en";
      language = "en";
      injectionMode = "both";
      keyDelay = 10;
      notify = true;
      silenceTimeout = 1.5;
      silenceThreshold = "5%"; # Less sensitive to background noise
    };

    # GitHub Actions Runner - Self-hosted CI/CD runner
    # Token is stored in encrypted age secret for security
    # To rotate token: regenerate in GitHub, then update secret with: age -r <public-key> -o secrets/github-actions-runner-token.age
    github-actions-runner = {
      enable = true;
      url = "https://github.com/reverb256/nixos-config";
      tokenFile = "/run/agenix/github-actions-runner-token";
      name = "zephyr";
    };

    # Llama.cpp AI Inference Server - Multi-GPU (RTX 3090 + RTX 3060 Ti)
    llama-server = {
      enable = true;
      # AI power limits (high for AI inference)
      aiPowerLimits = {
        "0" = 160;  # RTX 3060 Ti (card0, compute only)
        "1" = 350;  # RTX 3090 (card1, display + compute)
      };
      # Mining power limits (low, restored when llama-server stops)
      miningPowerLimits = {
        "0" = 130;  # RTX 3060 Ti mining
        "1" = 250;  # RTX 3090 mining
      };
    };
  };

  # ============================================================================
  # TAILSCALE ROUTING (Gateway for cluster)
  # ============================================================================
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # ============================================================================
  # USER GROUPS
  # ============================================================================
  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "tailscale" "video" "render"];

  # ============================================================================
  # BOOT SPECIALISATIONS
  # ============================================================================
  specialisation = {
    beta.configuration = {
      system.nixos.tags = ["beta"];
      hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta;
    };

    hyprland-niri.configuration = {
      system.nixos.tags = ["hyprland-niri"];
      # Disable Plasma/PLM, use SDDM for Hyprland/Niri
      services.desktopManager.plasma6.enable = lib.mkForce false;
      services.displayManager.plasma-login-manager.enable = lib.mkForce false;
      services.displayManager.sddm.enable = lib.mkForce true;
      services.displayManager.sddm.wayland.enable = lib.mkForce true;
      services.displayManager.sddm.settings.Users.HideUsers = lib.mkForce "mining;nixbuild;lobster";
    };

    nvidia-proprietary.configuration = {
      system.nixos.tags = ["nvidia-proprietary"];
      hardware.nvidia.wayland.openModules = lib.mkForce false;
      hardware.nvidia.open = lib.mkForce false;
    };

    nouveau.configuration = {
      system.nixos.tags = ["nouveau"];
      hardware.nvidia.open = lib.mkForce false;
      hardware.nvidia.wayland.enable = lib.mkForce false;
      services.xserver.videoDrivers = lib.mkForce ["nouveau"];
      boot.blacklistedKernelModules = ["nvidia" "nvidia_modeset" "nvidia_drm" "nvidia_uvm"];
      environment.sessionVariables.QT_QPA_PLATFORM = lib.mkForce "xcb";
    };

    x11.configuration = {
      system.nixos.tags = ["x11"];
      environment.sessionVariables.QT_QPA_PLATFORM = lib.mkForce "xcb";
      environment.sessionVariables.GDK_BACKEND = lib.mkForce "x11";
    };

    safe.configuration = {
      system.nixos.tags = ["safe-mode"];
      # Disable GPU acceleration, use Sway for lightweight WM
      hardware.nvidia.wayland.enable = lib.mkForce false;
      services.xserver.enable = lib.mkForce false;
      boot.kernelParams = ["nomodeset" "nouveau.modeset=0" "nvidia.modeset=0" "nvidia-drm.modeset=0"];
      boot.blacklistedKernelModules = ["nvidia" "nvidia_modeset" "nvidia_drm" "nouveau"];
      # Enable Sway as failsafe WM
      programs.sway.enable = true;
      services.displayManager.sddm.enable = lib.mkForce true;
    };
  };
}
