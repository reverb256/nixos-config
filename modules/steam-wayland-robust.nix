# Steam + Wayland + NVIDIA Configuration Module
# Robust configuration for Steam gaming on Wayland with NVIDIA
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options = {
    services.steamWayland.enable = mkEnableOption "Enable Steam with Wayland support";
    services.steamWayland.protonVersion = mkOption {
      type = types.str;
      description = "Proton version to use for Steam";
    };
    services.steamWayland.extraCompatPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional Steam compatibility packages";
    };
  };

  config = mkIf config.services.steamWayland.enable {
    # ============================================================================
    # STEAM CONFIGURATION - Wayland Optimized
    # ============================================================================

    programs.steam = {
      enable = true;

      # Proton configuration for Wayland
      extraCompatPackages = with pkgs;
        [
          cfg.protonVersion
        ]
        ++ cfg.extraCompatPackages;
    };

    # ============================================================================
    # NVIDIA WAYLAND SUPPORT - Conservative Configuration
    # ============================================================================

    # Use standard NVIDIA drivers instead of ZEN-specific
    hardware.nvidia = {
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      modesetting.enable = true;
      open = false;
      nvidiaSettings = true;
      powerManagement.enable = true;
    };

    # Kernel parameters optimized for Steam + Wayland
    boot.kernelParams = [
      # Basic NVIDIA Wayland support
      "nvidia-drm.modeset=1"
      "nvidia-uvm/uvm_disable_huge_pages=1" # Fix for SteamVR

      # Steam optimizations (minimal)
      "fsync.enable=1"
      "threadirqs"

      # Conservative CPU settings for gaming
      "amd_pstate=active"
      "mitigations=off"
      "transparent_hugepage=madvise"
      "numa_balancing=disable"
      "nowatchdog"

      # Remove aggressive parameters that break Steam
      # NO: isolcpus, nohz_full, rcu_nocbs
    ];

    # ============================================================================
    # ENVIRONMENT VARIABLES - Steam + Wayland
    # ============================================================================

    environment.sessionVariables = {
      # Force Wayland for desktop apps
      QT_QPA_PLATFORM = "wayland";
      GDK_BACKEND = "wayland";
      XDG_SESSION_TYPE = "wayland";

      # NVIDIA Wayland variables
      WLR_DRM_NO_MODIFIERS = "1";
      NVD_BACKEND = "direct";
      __NV_PRIME_RENDER_OFFLOAD = "1";

      # NVIDIA Wayland hardware acceleration (Fixes KDE Plasma fallback issues)
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      __EGL_VENDOR_LIBRARY_FILENAMES = "nvidia";
      # Steam-specific variables
      STEAM_FRAME_FORCE_CLOSE = "1";
      STEAM_LINUX_RUNTIME = 1;
      STEAM_USE_NVAPI = "1";

      # Proton variables
      PROTON_USE_WINED3D = "0"; # Use Vulkan
      DXVK_ASYNC = "1";
      DXVK_LOG_LEVEL = "warn";
      WINE_FULLSCREEN_FORCE_DESKTOP = "1";
    };

    # ============================================================================
    # SYSTEMD SERVICES - Gaming Optimization
    # ============================================================================

    # Steam runtime service
    systemd.services.steam-runtime = {
      description = "Steam Runtime Service";
      wantedBy = ["graphical-session.target"];
      after = ["graphical-session.target"];
      script = ''
        # Wait for Steam to be ready
        sleep 5

        # Set Steam environment
        export STEAM_FRAME_FORCE_CLOSE=1
        export STEAM_LINUX_RUNTIME=1
        export STEAM_USE_NVAPI=1

        # Start Steam services
        /run/current-system/sw/bin/steam -silent &
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # ============================================================================
    # PACKAGES - Steam + Gaming Ecosystem
    # ============================================================================

    environment.systemPackages = with pkgs; [
      # Core Steam packages
      steam
      steam-run

      # Proton packages

      # Gaming utilities
      gamescope
      mangohud
      goverlay

      # NVIDIA utilities
      nvidia-x11
      nvidia-vaapi-driver

      # Wayland gaming support
      wlroots
      gamescope-session

      # Audio for gaming
      pulseaudio-full

      # Debugging tools
      vulkan-tools
      nvidia-nsight
    ];

    # ============================================================================
    # UDEV RULES - Steam Controller and VR Support
    # ============================================================================

    services.udev.extraRules = ''
      # Steam Controller
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", MODE="0666", GROUP="plugdev"

      # HTC Vive
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2000", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2101", MODE="0666", GROUP="plugdev"

      # Valve Index
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2000", MODE="0666", GROUP="plugdev"

      # Quest/Quest Pro (when connected via USB)
      SUBSYSTEM=="usb", ATTRS{idVendor}=="2833", MODE="0666", GROUP="plugdev"
    '';

    # ============================================================================
    # ASSERTIONS - Configuration Validation
    # ============================================================================

    assertions = [
      {
        assertion = config.programs.steam.enable;
        message = "Steam must be enabled for gaming support";
      }
      {
        assertion = config.hardware.nvidia.package != null;
        message = "NVIDIA drivers are required for RTX 3090";
      }
      {
        assertion = config.services.xserver.enable;
        message = "X11 must be enabled for Steam compatibility layer";
      }
    ];
  };
}
