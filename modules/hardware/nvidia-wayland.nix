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
      description = "Use open-source NVIDIA kernel modules (required for driver 560+)";
    };

    powerManagement = lib.mkOption {
      type = lib.types.bool;
      default = false;  # DISABLED - causes freezes with multi-GPU + Wayland
      description = "Enable NVIDIA power management";
    };

    sddmWayland = lib.mkOption {
      type = lib.types.bool;
      default = false;  # Disabled in favor of plasma-login-manager (Plasma 6.6)
      description = "Enable SDDM Wayland support (deprecated, use plasma-login-manager)";
    };

    # Multi-GPU support
    multiGpu = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable multi-GPU configuration";
      };

      primaryCard = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/dev/dri/card1";
        description = "Primary GPU device path for KWin (the one with monitors attached)";
      };
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
      inherit (cfg) enable32Bit;

      extraPackages = with pkgs; [
        # Essential for NVIDIA + Wayland integration
        egl-wayland

        # Hardware video acceleration
        nvidia-vaapi-driver
        libva
        libva-utils
      ];

      extraPackages32 = lib.optionals cfg.enable32Bit (
        with pkgs.pkgsi686Linux; [
          nvidia-vaapi-driver
        ]
      );
    };

    # ============================================================================
    # DISPLAY MANAGER (SDDM with Wayland)
    # ============================================================================
    services.displayManager.sddm = {
      wayland.enable = lib.mkDefault cfg.sddmWayland;
      settings.Users.HideUsers = "mining;nixbuild;lobster";
    };

    # ============================================================================
    # ENVIRONMENT VARIABLES (Minimal, working NVIDIA + Wayland)
    # ============================================================================
    environment.sessionVariables =
      {
        # Force Wayland backend for Qt applications (Plasma 6)
        QT_QPA_PLATFORM = "wayland";

        # Enable Wayland for Ozone-based applications (Chrome, Electron, etc.)
        NIXOS_OZONE_WL = "1";

        # CRITICAL: Force NVIDIA Vulkan ICD
        VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";

        # Ensure GLX uses NVIDIA vendor library
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";

        # Force GBM to use NVIDIA DRM backend (CRITICAL for Plasma 6 Wayland)
        GBM_BACKEND = "nvidia-drm";

        # VA-API driver for hardware video acceleration
        LIBVA_DRIVER_NAME = "nvidia";

        # CRITICAL: EGL vendor library path for Qt6/KWin
        __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";
      }
      // lib.optionalAttrs (cfg.multiGpu.enable && cfg.multiGpu.primaryCard != null) {
        # Multi-GPU: Tell KWin which GPU to use for display
        KWIN_DRM_DEVICES = cfg.multiGpu.primaryCard;
      };

    # ============================================================================
    # ADDITIONAL WAYLAND PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [
      # Wayland utilities
      wayland-utils

      # Display management
      kanshi
    ];

    # ============================================================================
    # VULKAN ICD SYMLINK
    # ============================================================================
    systemd.tmpfiles.rules = [
      "L+ /etc/vulkan/icd.d/nvidia_icd.json - - - /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
      "L+ /etc/vulkan/icd.d/nvidia_icd.x86_64.json - - - /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
      "d /etc/vulkan/icd.d 0755 root root -"
    ];

    # ============================================================================
    # KERNEL PARAMETERS
    # ============================================================================
    boot.kernelParams = [
      "nvidia-drm.modeset=1"
    ];

    # ============================================================================
    # EARLY NVIDIA LOADING
    # ============================================================================
    boot.initrd.kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_drm"
    ];

    boot.initrd.availableKernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_drm"
    ];

    # ============================================================================
    # NVIDIA DEVICE NODE CREATION
    # ============================================================================
    systemd.services.nvidia-device-nodes = {
      description = "Create NVIDIA device nodes";
      after = [
        "systemd-modules-load.service"
        "systemd-udev-trigger.service"
      ];
      wants = ["systemd-modules-load.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "nvidia-device-nodes" ''
          if [ -d /proc/driver/nvidia ]; then
            if [ ! -e /dev/nvidiactl ]; then
              mknod -m 666 /dev/nvidiactl c 195 255 2>/dev/null || true
            fi
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
