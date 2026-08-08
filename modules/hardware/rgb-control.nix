# RGB backend ownership and package support.
#
# Hardware discovery and Stylix writes are provided by services.rgb-inventory.
# This module intentionally does not contain a second temperature-driven writer:
# one host must have one RGB owner, and fan/PWM control remains separate.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.rgb-control;
in {
  options.hardware.rgb-control = {
    enable = lib.mkEnableOption "RGB backend support and inventory integration";

    openrgb = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the native OpenRGB backend for RGB hardware.";
      };

      motherboard = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum ["amd" "intel"]);
        default = null;
        description = "Optional motherboard CPU family for OpenRGB SMBus access.";
      };
    };

    openrazer.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable OpenRAZER support for Razer peripherals.";
    };

    wraithRgb.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install AMD Wraith RGB tooling when its controller is verified.";
    };

    # Kept as compatibility metadata for existing host declarations. Actual
    # color policy belongs to Stylix and services.rgb-inventory.controlDevices.
    temperatureReactive.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Deprecated; temperature RGB writes are not provided by this module.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      lib.optionals cfg.openrgb.enable [
        pkgs.openrgb-plugin-effects
        pkgs.python3Packages.openrgb-python
      ]
      ++ lib.optionals cfg.openrazer.enable [
        pkgs.polychromatic
        pkgs.razer-cli
      ]
      ++ lib.optionals cfg.wraithRgb.enable [pkgs.cm-rgb];

    # The native NixOS module is the sole OpenRGB SDK server owner.
    services.hardware.openrgb = lib.mkIf cfg.openrgb.enable {
      enable = true;
      motherboard = cfg.openrgb.motherboard;
    };

    boot.kernelModules = lib.optionals cfg.openrazer.enable [
      "razeraccessory"
      "razerkbd"
      "razerkraken"
      "razermouse"
    ];

    hardware.openrazer = lib.mkIf cfg.openrazer.enable {
      enable = true;
      users = ["j_kro"];
    };

    boot.extraModulePackages = lib.optionals cfg.openrazer.enable [
      config.boot.kernelPackages.openrazer
    ];
  };
}
