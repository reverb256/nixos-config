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
      example = false;
      description = "Enable 32-bit graphics support for Steam and games";
    };

    openModules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Use open-source NVIDIA kernel modules (recommended for Wayland since driver 560+)";
    };

    powerManagement = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Enable NVIDIA power management";
    };

    sddmWayland = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Enable SDDM Wayland support";
    };
  };

  config = lib.mkIf cfg.enable {
    # ============================================================================
    # NVIDIA DRIVER CONFIGURATION
    # ============================================================================
    # NOTE: hardware.nvidia base configuration (including package) is in nvidia-common.nix
    # This module only adds/overrides Wayland-specific settings
    hardware.nvidia = {
      open = cfg.openModules;
      modesetting.enable = true;
      nvidiaSettings = true;
      powerManagement.enable = cfg.powerManagement;
      powerManagement.finegrained = false;
      gsp.enable = cfg.openModules;
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

      # CRITICAL: Force NVIDIA Vulkan ICD (fixes DXVK initialization failures)
      # Without this, Vulkan loader can't find the NVIDIA driver
      VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";

      # Ensure GLX uses NVIDIA vendor library
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";

      # Force GBM to use NVIDIA DRM backend (fixes DMA-BUF/EGL buffer import issues)
      GBM_BACKEND = "nvidia-drm";

      # VA-API driver for hardware video acceleration
      LIBVA_DRIVER_NAME = "nvidia";

      # Disable G-SYNC to prevent buffer issues
      __GL_GSYNC_ALLOWED = "0";

      # Disable VRR for stability (can re-enable later)
      __GL_VRR_ALLOWED = "0";

      # Disable hardware cursors for Wayland stability
      WLR_NO_HARDWARE_CURSORS = "1";

      # Additional variables for NVIDIA EGL and NVENC
      NVD_BACKEND = "direct";
      __NV_PRIME_RENDER_OFFLOAD = "1";

      # Disable sync to vblank for stability
      __GL_SYNC_TO_VBLANK = "0";

      # VRChat/SteamVR specific variables
      # SDL_VIDEODRIVER = "wayland";  # REMOVED: Causes Steam Vulkan init failure
      # SDL auto-detects best backend; Steam client needs XWayland fallback
      WINEPREFIX = "$HOME/.wine";
      DXVK_HUD = "1"; # Enable to debug VRChat performance if needed (remove later)
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
    # VULKAN ICD SYMLINK - Create symlink in /etc/vulkan/icd.d for standard loader
    # NixOS uses /run/opengl-driver which isn't in default search paths
    # ============================================================================
    systemd.tmpfiles.rules = [
      "L+ /etc/vulkan/icd.d/nvidia_icd.json - - - /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
      "L+ /etc/vulkan/icd.d/nvidia_icd.x86_64.json - - - /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
      "d /etc/vulkan/icd.d 0755 root root -"
    ];

    # ============================================================================
    # KERNEL PARAMETERS (for better Wayland stability)
    # ============================================================================
    boot = {
      kernelParams = [
        # Enable NVIDIA DRM modeset (required for Wayland)
        "nvidia-drm.modeset=1"
      ];

      # EARLY NVIDIA LOADING - Fix race condition with simple-framebuffer
      # Load NVIDIA modules in initramfs before simple-framebuffer claims displays
      initrd = {
        kernelModules = [
          "nvidia"
          "nvidia_modeset"
          "nvidia_drm"
        ];

        # Also ensure modules are available in initramfs
        availableKernelModules = [
          "nvidia"
          "nvidia_modeset"
          "nvidia_drm"
        ];
      };
    };

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
        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = ["AF_UNIX"];
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
