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
    ../../modules/services/whisper-dictation.nix
    ../../modules/system/system-services.nix
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
  services.displayManager.sddm.enable = lib.mkForce false;  # Disable SDDM first
  services.displayManager.plasma-login-manager.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "j_kro";
  };

  # Enable NVIDIA Wayland optimizations
  hardware.nvidia.wayland.enable = true;

  # Multi-GPU: RTX 3090 (card2) has all 4 displays, RTX 3060 Ti (card1) is compute-only
  hardware.nvidia.wayland.multiGpu = {
    enable = true;
    autoDetect = false;  # Use explicit values
    primaryCard = "/dev/dri/card2";  # RTX 3090 (display GPU)
    secondaryCard = "/dev/dri/card1";  # RTX 3060 Ti (compute-only)
  };

  # ============================================================================
  # GAMING + VR (Full support - RTX 3090)
  # ============================================================================
  services.gaming = {
    enable = true;
    vr.enable = true; # WiVRn, SteamVR, OpenXR
  };

  # HoYoverse controller fix (DualSense/DualShock)
  # DISABLED: Causes 90-second timeout on boot (winedevice.exe hangs)
  # services.hoyoverse-controller-fix.enable = true;

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
      allowedTCPPorts = [9757];
      allowedUDPPorts = [9757 9758 9759 27031 27036 5353 9947];
      # SSH only from local network and Tailscale
      interfaces."enp38s0".allowedTCPPorts = [22];  # Local network 10.1.1.0/24
      interfaces."tailscale0".allowedTCPPorts = [22 18789 18790];
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

    # Mining (both GPUs: RTX 3060 Ti @ 130W + RTX 3090 @ 250W)
    mining = {
      enable = true;
      xmrig = {
        enable = true;
        threads = 16;
      };
      lolminer = {
        enable = true;
        nvidia = {
          enable = true;
          devices = "1";  # Only RTX 3090 (card1) - GPU0 used by llama.cpp
          perGpuPowerLimits = {
            "0" = 130;  # RTX 3060 Ti - compute only
            "1" = 250;  # RTX 3090 - display + compute
          };
        };
      };
    };

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
      # Multi-GPU tensor split: Both GPUs for Qwen model (no mining on GPU0)
      # GPU0 (3060 Ti, 8GB): 7680MiB for KV cache (Q4_0 with 256K context ≈ 6-7GB)
      # GPU1 (RTX 3090, 24GB): 21504MiB for model weights + ~2.5GB for display
      # Total: ~29GB model + cache fits in combined 32GB VRAM
      tensorSplit = "7680,21504";
      # Context size - Qwen3.5 supports up to 131072 tokens
      contextSize = 262144;  # 256K tokens maximum for Qwen3.5-35B-A3B
      # Cache settings - Q4_0 for efficiency (fits in GPU0 allocation)
      cacheTypeK = "q4_0";
      cacheTypeV = "q4_0";
      # Sampling parameters for coding/technical tasks
      temperature = 0.6;
      topP = 0.95;
      topK = 20;
      # AI power limits - Both GPUs used for AI
      aiPowerLimits = {
        "0" = 200;  # RTX 3060 Ti (full KV cache)
        "1" = 350;  # RTX 3090 (model + display)
      };
      # Mining power limits (restored when llama-server stops)
      miningPowerLimits = {
        "0" = 130;  # RTX 3060 Ti (currently not used for mining)
        "1" = 250;  # RTX 3090 mining (GPU1 used for AI when llama-server runs)
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
  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "tailscale" "video" "render" "uinput"];

  # ============================================================================
  # HOST-SPECIFIC FIXES
  # ============================================================================
  # Ydotoold - Fix permissions for /dev/uinput access (daemon security)
  systemd.services.ydotoold = {
    serviceConfig = {
      CapabilityBoundingSet = ["CAP_SYS_ADMIN"];
      AmbientCapabilities = ["CAP_SYS_ADMIN"];
      PrivateDevices = lib.mkForce false;
      SystemCallFilter = lib.mkForce null;
      ProtectSystem = lib.mkForce false;
      ProtectHome = lib.mkForce false;
      ProtectKernelTunables = lib.mkForce false;
      ProtectKernelModules = lib.mkForce false;
      ProtectControlGroups = lib.mkForce false;
      RestrictAddressFamilies = lib.mkForce null;
      RestrictRealtime = lib.mkForce false;
      RestrictSUIDSGID = lib.mkForce false;
      LockPersonality = lib.mkForce false;
      MemoryDenyWriteExecute = lib.mkForce false;
      SystemCallArchitectures = lib.mkForce null;
      NoNewPrivileges = lib.mkForce false;
      PrivateTmp = lib.mkForce false;
    };
  };

  # uinput device access
  services.udev.extraRules = ''
    KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS="static_node=uinput"
  '';

  # Fail2ban - Remove non-existent sshd-ddos filter
  services.fail2ban.jails = {
    sshd-ddos = lib.mkForce {};
  };

  # Networking - Disable IPv4 forwarding (not needed)
  boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkForce false;

  # ============================================================================
  # BOOT SPECIALISATIONS
  # ============================================================================
  specialisation = {
    # Beta NVIDIA driver - Plasma Wayland with autologin
    beta.configuration = {
      system.nixos.tags = ["beta"];
      hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta;
      services.displayManager.autoLogin.enable = lib.mkForce true;
      services.displayManager.autoLogin.user = lib.mkForce "j_kro";
    };

    # Hyprland/Niri - SDDM with session selection (NO autologin)
    hyprland-niri.configuration = {
      system.nixos.tags = ["hyprland-niri"];
      # Enable Niri compositor
      programs.niri.enable = true;
      # Disable SSH agent to avoid conflict with gcr-ssh-agent
      programs.ssh.startAgent = lib.mkForce false;
      # Disable Plasma/PLM, use SDDM for Hyprland/Niri
      services.desktopManager.plasma6.enable = lib.mkForce false;
      services.displayManager.plasma-login-manager.enable = lib.mkForce false;
      services.displayManager.sddm.enable = true;
      services.displayManager.sddm.wayland.enable = true;
      # Disable autologin - user chooses between Hyprland/Niri
      services.displayManager.autoLogin.enable = lib.mkForce false;
      services.displayManager.sddm.settings = {
        General = {
          DisplayServer = "wayland";
        };
        Users = {
          HideUsers = "mining;nixbuild;lobster";
        };
      };
    };

    # Proprietary NVIDIA driver - Plasma Wayland with autologin
    nvidia-proprietary.configuration = {
      system.nixos.tags = ["nvidia-proprietary"];
      hardware.nvidia.wayland.openModules = lib.mkForce false;
      hardware.nvidia.open = lib.mkForce false;
      services.displayManager.autoLogin.enable = lib.mkForce true;
      services.displayManager.autoLogin.user = lib.mkForce "j_kro";
    };

    # Nouveau (open source) - Plasma X11 with autologin
    nouveau.configuration = {
      system.nixos.tags = ["nouveau"];
      hardware.nvidia.open = lib.mkForce false;
      hardware.nvidia.wayland.enable = lib.mkForce false;
      services.xserver.videoDrivers = lib.mkForce ["nouveau"];
      boot.blacklistedKernelModules = ["nvidia" "nvidia_modeset" "nvidia_drm" "nvidia_uvm"];
      environment.sessionVariables.QT_QPA_PLATFORM = lib.mkForce "xcb";
      # Force Plasma X11 session
      services.displayManager.defaultSession = lib.mkForce "plasma";
      services.displayManager.autoLogin.enable = lib.mkForce true;
      services.displayManager.autoLogin.user = lib.mkForce "j_kro";
    };

    # X11 - Plasma X11 with autologin
    x11.configuration = {
      system.nixos.tags = ["x11"];
      environment.sessionVariables.QT_QPA_PLATFORM = lib.mkForce "xcb";
      environment.sessionVariables.GDK_BACKEND = lib.mkForce "x11";
      # Force Plasma X11 session
      services.displayManager.defaultSession = lib.mkForce "plasma";
      services.displayManager.autoLogin.enable = lib.mkForce true;
      services.displayManager.autoLogin.user = lib.mkForce "j_kro";
    };

    # Safe mode - Sway with autologin
    safe.configuration = {
      system.nixos.tags = ["safe-mode"];
      # Disable GPU acceleration, use Sway for lightweight WM
      hardware.nvidia.wayland.enable = lib.mkForce false;
      # Disable Plasma/PLM, use SDDM for Sway
      services.desktopManager.plasma6.enable = lib.mkForce false;
      services.displayManager.plasma-login-manager.enable = lib.mkForce false;
      services.displayManager.sddm.enable = true;
      services.displayManager.defaultSession = lib.mkForce "sway";
      services.displayManager.autoLogin.enable = lib.mkForce true;
      services.displayManager.autoLogin.user = lib.mkForce "j_kro";
    };
  };
}
