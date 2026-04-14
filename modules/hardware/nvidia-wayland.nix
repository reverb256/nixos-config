{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.nvidia.wayland;
in
{
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


    hardware.nvidia = {
      open = cfg.openModules;
      modesetting.enable = true;
      nvidiaSettings = true;
      powerManagement.enable = lib.mkForce cfg.powerManagement;
      powerManagement.finegrained = false;
      gsp.enable = cfg.openModules;
    };


    services.displayManager.sddm.wayland.enable = lib.mkDefault cfg.sddmWayland;


    environment.sessionVariables = {
      VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      GBM_BACKEND = "nvidia-drm";
      LIBVA_DRIVER_NAME = "nvidia";
      __GL_GSYNC_ALLOWED = "0";
      __GL_VRR_ALLOWED = "0";
      NVD_BACKEND = "direct";
      __GL_SYNC_TO_VBLANK = "0";
    };


    environment.systemPackages = with pkgs; [
      wayland-utils
      kanshi
      gamemode
    ];

    environment.etc = {
      "vulkan/icd.d/nvidia_icd.json".source =
        "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
      "vulkan/icd.d/nvidia_icd.x86_64.json".source =
        "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
    };


    boot = {
      kernelParams = [
        "nvidia-drm.modeset=1"
        "nvidia-drm.fbdev=1"
        "nvidia.NVreg_DynamicPowerManagement=0x00"
      ];
      initrd = {
        kernelModules = [
          "nvidia"
          "nvidia_modeset"
          "nvidia_drm"
        ];
        availableKernelModules = [
          "nvidia"
          "nvidia_modeset"
          "nvidia_drm"
        ];
      };
    };


    systemd.services.nvidia-device-nodes = {
      description = "Create NVIDIA device nodes";
      after = [
        "systemd-modules-load.service"
        "systemd-udev-trigger.service"
      ];
      wants = [ "systemd-modules-load.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
        ExecStart = pkgs.writeShellScript "nvidia-device-nodes" ''
          if [ -d /proc/driver/nvidia ]; then
            if [ ! -e /dev/nvidiactl ]; then
              mknod -m 660 /dev/nvidiactl c 195 255 2>/dev/null || true
            fi
            if [ -d /proc/driver/nvidia/gpus ]; then
              for gpu in /proc/driver/nvidia/gpus/*; do
                if [ -d "$gpu" ]; then
                  minor=$(grep -oP 'Minor:\s*\K[0-9]+' "$gpu/information" 2>/dev/null || true)
                  if [ -n "$minor" ] && [ ! -e "/dev/nvidia$minor" ]; then
                    mknod -m 660 "/dev/nvidia$minor" c 195 "$minor" 2>/dev/null || true
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
