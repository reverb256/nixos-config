{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.nvidia-common;
in {
  options.hardware.nvidia-common.enable = lib.mkEnableOption "NVIDIA GPU support";

  config = lib.mkIf cfg.enable {
    hardware.graphics = {
      enable = lib.mkDefault true;
      enable32Bit = lib.mkDefault false;

      extraPackages = with pkgs; [
        vulkan-loader
        vulkan-tools
      ];
    };

    services.xserver.videoDrivers = ["nvidia"];

    hardware.nvidia = {
      modesetting.enable = true;

      powerManagement.enable = false;

      package = config.boot.kernelPackages.nvidiaPackages.new_feature;

      open = true;

      nvidiaSettings = true;
    };

    boot.extraModprobeConfig = ''
      options nvidia NVreg_EnableGpuFirmware=1

      options nvidia NVreg_DynamicPowerManagement=0
    '';

    hardware.nvidia-container-toolkit = {
      enable = lib.mkDefault true;
      mount-nvidia-executables = true;
    };

    systemd.services.nvidia-container-toolkit-cdi-generator = {
      unitConfig.OnFailure = "";
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      serviceConfig.SuccessExitStatus = "0 1";
    };

    systemd.services.nvidia-persistence-mode = {
      description = "Enable NVIDIA GPU persistence mode";
      wantedBy = ["multi-user.target"];
      after = ["systemd-modules-load.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.hardware.nvidia.package.bin}/bin/nvidia-smi -pm 1";
      };
    };
  };
}
