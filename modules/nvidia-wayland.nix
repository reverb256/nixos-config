# NVIDIA Wayland Module - Best Practices for NVIDIA + Wayland + Plasma 6
# Based on NixOS community best practices as of 2026
# Reference: https://wiki.nixos.org/wiki/NVIDIA
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.nvidia.wayland;
in {
  options.hardware.nvidia.wayland = {
    enable = lib.mkEnableOption "NVIDIA Wayland optimizations for Plasma 6";

    enable32Bit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable 32-bit graphics support for Steam and games";
    };

    openModules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use open-source NVIDIA kernel modules (recommended for Wayland since driver 560+)";
    };

    powerManagement = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable NVIDIA power management";
    };

    sddmWayland = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SDDM Wayland support";
    };
  };

  config = lib.mkIf cfg.enable {
    # ============================================================================
    # NVIDIA DRIVER CONFIGURATION
    # ============================================================================
    hardware.nvidia = {
      # Use open-source modules for better Wayland support (driver 560+)
      open = cfg.openModules;

      # Required for Wayland
      modesetting.enable = true;

      # NVIDIA settings GUI
      nvidiaSettings = true;

      # Power management
      powerManagement.enable = cfg.powerManagement;
      powerManagement.finegrained = false;
      
      # Disable GSP firmware for better stability with RTX 3090
      gsp.enable = false;
    };

    # ============================================================================
    # GRAPHICS CONFIGURATION
    # ============================================================================
    hardware.graphics = {
      enable = true;
      enable32Bit = cfg.enable32Bit;

      extraPackages = with pkgs; [
        # Essential for NVIDIA + Wayland integration
        egl-wayland

        # Hardware video acceleration
        nvidia-vaapi-driver
        libva
        libva-utils
      ];

      extraPackages32 = lib.optionals cfg.enable32Bit (with pkgs.pkgsi686Linux; [
        nvidia-vaapi-driver
      ]);
    };

    # ============================================================================
    # DISPLAY MANAGER (SDDM with Wayland)
    # ============================================================================
    services.displayManager.sddm.wayland.enable = cfg.sddmWayland;

    # ============================================================================
    # ENVIRONMENT VARIABLES (Critical for NVIDIA + Wayland)
    # ============================================================================
    environment.sessionVariables = {
      # Force Wayland backend for Qt applications (Plasma 6)
      QT_QPA_PLATFORM = "wayland";

      # Enable Wayland for Ozone-based applications (Chrome, Electron, etc.)
      NIXOS_OZONE_WL = "1";

      # Enable Wayland for Firefox
      MOZ_ENABLE_WAYLAND = "1";

      # Force VA-API to use NVIDIA driver (prevents simpledrm fallback)
      LIBVA_DRIVER_NAME = "nvidia";

      # Ensure GLX uses NVIDIA vendor library
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";

      # Force GBM to use NVIDIA DRM backend (fixes DMA-BUF/EGL buffer import issues)
      GBM_BACKEND = "nvidia-drm";

      # Disable G-SYNC to prevent buffer issues
      __GL_GSYNC_ALLOWED = "0";

      # Disable VRR for stability (can re-enable later)
      __GL_VRR_ALLOWED = "0";

      # Disable hardware cursors for Wayland stability
      WLR_NO_HARDWARE_CURSORS = "1";

      # Additional variables for NVIDIA EGL and NVENC
      NVD_BACKEND = "direct";
      __NV_PRIME_RENDER_OFFLOAD = "1";
    };

    # ============================================================================
    # ADDITIONAL WAYLAND PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [
      # Wayland utilities
      wayland-utils

      # Display management
      kanshi

      # NVIDIA monitoring
      nvtopPackages.full
    ];

    # ============================================================================
    # KERNEL PARAMETERS (for better Wayland stability)
    # ============================================================================
    boot.kernelParams = [
      # Enable NVIDIA DRM modeset (required for Wayland)
      "nvidia-drm.modeset=1"

      # Disable fbdev for better Wayland support (optional, may help stability)
      "nvidia_drm.fbdev=0"
    ];
  };
}
