{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.amdgpu.wayland;
in {
  options.hardware.amdgpu.wayland = {
    enable = lib.mkEnableOption "AMD GPU Wayland optimizations for Plasma 6";

    enable32Bit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Enable 32-bit graphics support for Steam and games";
    };

    opencl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Enable OpenCL support via ROCm";
    };

    sddmWayland = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Enable SDDM Wayland support";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.amdgpu = {
      opencl.enable = cfg.opencl;

      initrd.enable = true;
    };

    hardware.graphics = {
      enable = lib.mkDefault true;
      inherit (cfg) enable32Bit;

      extraPackages = with pkgs; [
        mesa
      ];

      extraPackages32 = lib.optionals cfg.enable32Bit (with pkgs.pkgsi686Linux; [
        mesa
      ]);
    };

    services.displayManager.sddm.wayland.enable = lib.mkDefault cfg.sddmWayland;

    environment.sessionVariables = {
      QT_QPA_PLATFORM = lib.mkDefault "wayland";

      NIXOS_OZONE_WL = "1";

      MOZ_ENABLE_WAYLAND = "1";

      ROC_ENABLE_PRE_VEGA = lib.mkIf cfg.opencl "1";
    };

    environment.systemPackages = with pkgs; [
      wayland-utils
      kanshi
    ];
  };
}
