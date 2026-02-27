# Zephyr Host Configuration - Master Workstation
# 10.1.1.110 - 32 cores, RTX 3090
# Features: Gaming + VR, Stability Matrix, Nix Cache Server, MCP Servers
{
  pkgs,
  lib,
  ...
}: {
  imports = [
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Common host imports (desktop, gaming, networking, etc.)
    ../../modules/common-host.nix

    # NVIDIA GPU support (common + wayland-specific)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix

    # Alternative desktop environment (Hyprland)
    ../../modules/desktop/hyprland.nix

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
  # ALTERNATIVE DESKTOP ENVIRONMENT (Hyprland)
  # ============================================================================
  programs.hyprland.enable = true;

  # Display Manager - Both Plasma and Hyprland available in SDDM
  # Users can select at login: Plasma (default) or Hyprland

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
  # NVIDIA CONFIGURATION
  # Note: Base config is in nvidia-common.nix
  # ============================================================================
  # Zephyr-specific kernel params (appended after nvidia-common.nix defaults)
  boot.kernelParams = lib.mkAfter [
    "split_lock_detect=off"
    "threadirqs"
    "preempt=full"
    "processor.max_cstate=1"
    "intel_idle.max_cstate=1"
    "iommu=pt"
  ];

  # ============================================================================
  # SERVICES
  # ============================================================================
  services = {
    garnix.enable = true;
    nixos-auto-update.enable = true;

    # Mining configuration - uses RTX 3060 Ti (GPU 0) only
    # Display uses RTX 3090 (GPU 1) - no conflict when configured correctly
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
          devices = "0";
          powerLimit = 250;
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

    # Llama.cpp AI Inference Server - Multi-GPU with Maximum Context
    # Uses both RTX 3090 (24GB) and RTX 3060 Ti (8GB) for distributed inference
    # Automatically stops mining service when running (conflicts directive)
    llama-server = {
      enable = true;

      # Maximum natural context window for Qwen3.5-35B-A3B model
      contextSize = 262144;  # Model's native 262K tokens

      # Multi-GPU configuration
      enableMultiGpu = true;
      multiGpuMode = "layer";  # Split layers across both GPUs
      mainGpu = null;  # Auto-select main GPU (will be 3090)

      # GPU layers offloading
      gpuLayers = 99;  # Offload almost all layers to GPU

      # Performance tuning
      enableFlashAttention = true;
      enableMetrics = true;
      parallelSlots = 1;
      ubatchSize = 1024;
      batchSize = 2048;

      # Sampling parameters
      temperature = 0.7;
      topP = 0.9;
      topK = 20;
      repeatPenalty = 1.05;
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
  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "openrazer" "tailscale" "video" "render"];

  # ============================================================================
  # CUDA ENVIRONMENT
  # ============================================================================
  environment.variables = {
    CUDA_PATH = "/run/opengl-driver";
    CUDA_HOME = "/run/opengl-driver";
    # KWin DRM devices - restrict to primary GPU only (RTX 3090)
    # Prevents KWin from trying to open mining GPU (RTX 3060 Ti) which causes session crash
    KWIN_DRM_DEVICES = "/dev/dri/card2";
  };
  environment.variables.LD_LIBRARY_PATH = pkgs.lib.mkForce "/run/opengl-driver/lib:/run/opengl-driver/lib64";
}
