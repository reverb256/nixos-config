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

      # GSP firmware - must be enabled when using open-source modules
      # Can be disabled for proprietary modules on RTX 3090 for stability
      gsp.enable = cfg.openModules;
    };

    # Include NVIDIA firmware when using open modules (required for GSP)
    hardware.firmware = lib.optionals cfg.openModules [
      config.hardware.nvidia.package.firmware
    ];

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
    services.displayManager.sddm.wayland.enable = lib.mkDefault cfg.sddmWayland;

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

      # Explicit Sync workarounds for Plasma 6 + NVIDIA stability
      # Fixes panel freeze when using dodge windows/auto-hide
      KWIN_DRM_NO_AMS = "1";  # Disable explicit sync for stability
      __GL_MaxFramesAllowed = "1";  # Reduce frame latency
    };

    # ============================================================================
    # ADDITIONAL WAYLAND PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [
      # Wayland utilities
      wayland-utils

      # Display management
      kanshi

      # Note: nvtop is provided by system-packages.nix to avoid rebuilds
      # nvtopPackages.full causes kernel-dependent rebuilds
    ];

    # ============================================================================
    # KERNEL PARAMETERS (for better Wayland stability)
    # ============================================================================
    boot.kernelParams = [
      # Enable NVIDIA DRM modeset (required for Wayland)
      "nvidia-drm.modeset=1"

      # Enable fbdev for proper display initialization
      # DISABLED: fbdev=0 causes black screen on boot
      # "nvidia_drm.fbdev=0"
    ];

    # ============================================================================
    # EARLY NVIDIA LOADING - Fix race condition with simple-framebuffer
    # Load NVIDIA modules in initramfs before simple-framebuffer claims displays
    # ============================================================================
    boot.initrd.kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_drm"
    ];

    # Also ensure modules are available in initramfs
    boot.initrd.availableKernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_drm"
    ];

    # ============================================================================
    # NVIDIA DEVICE NODE CREATION - Ensure device nodes exist after driver load
    # Fixes udev race condition where device nodes aren't created during early boot
    # ============================================================================
    systemd.services.nvidia-device-nodes = {
      description = "Create NVIDIA device nodes";
      after = ["systemd-modules-load.service" "systemd-udev-trigger.service"];
      wants = ["systemd-modules-load.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "nvidia-device-nodes" ''
          # Wait for NVIDIA driver to be fully loaded
          if [ -d /proc/driver/nvidia ]; then
            # Create control device if it doesn't exist
            if [ ! -e /dev/nvidiactl ]; then
              mknod -m 666 /dev/nvidiactl c 195 255 2>/dev/null || true
            fi
            
            # Create GPU devices
            if [ -d /proc/driver/nvidia/gpus ]; then
              for gpu in /proc/driver/nvidia/gpus/*; do
                if [ -d "$gpu" ]; then
                  minor=$(grep -oP 'Minor:\s*\K[0-9]+' "$gpu/information" 2>/dev/null || true)
                  if [ -n "$minor" ] && [ ! -e "/dev/nvidia$minor" ]; then
                    mknod -m 666 "/dev/nvidia$minor" c 195 "$minor" 2>/dev/null || true
                  fi
                fi
              done
            fi
          fi
        '';
      };
    };
  };
}
