# Corsair Hardware Support Module
# Provides support for Corsair AIO coolers, RGB controllers, and fan controllers
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.corsair;
in
{
  options.hardware.corsair = {
    enable = lib.mkEnableOption "Corsair hardware support (AIO, RGB, fan controllers)";

    # AIO cooler support (liquidctl)
    aio.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Corsair AIO cooler support via liquidctl";
    };

    # RGB control (OpenRGB)
    rgb.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable OpenRGB for Corsair RGB control";
    };

    # Kernel modules for Corsair devices
    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "corsair-cwi"      # Corsair USB input driver
        "usbhid"           # Generic USB HID support
        "hid Corsair"       # Alternative HID module
      ];
      description = "Kernel modules for Corsair devices";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install Corsair-related packages
    environment.systemPackages = with pkgs; [
      liquidctl    # Corsair AIO cooler control
      openrgb      # OpenRGB for RGB control
    ] ++ lib.optionals cfg.aio.enable [
      # Optional AIO tools
    ] ++ lib.optionals cfg.rgb.enable [
      # OpenRGB plugins
      openrgb-plugin-effects
    ];

    # Load kernel modules for Corsair devices
    boot.kernelModules = cfg.kernelModules;

    # USB device access for non-root users
    services.udev.extraRules = ''
      # Corsair H115i/H100i AIO coolers (vendor 1b1c, product 1b38)
      ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="1b38", MODE="0666"

      # Corsair Commander Core/Pro (vendor 1b1c, product 0c0b)
      ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="0c0b", MODE="0666"

      # Corsair Lighting Node/PSU (vendor 1b1c, product 0c13)
      ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="0c13", MODE="0666"

      # Generic Corsair devices
      ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", MODE="0666"

      # HID devices for OpenRGB
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1b1c", MODE="0666"
      ACTION=="add|change", KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1b1c", MODE="0666"

      # OpenRGB udev rules
      SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", TAG+="uaccess"
      KERNEL=="hidraw*", ATTRS{idVendor}=="1b1c", TAG+="uaccess"
    '';

    # Optional: OpenRGB service for auto-start
    systemd.services.openrgb = lib.mkIf cfg.rgb.enable {
      description = "OpenRGB RGB lighting control";
      wantedBy = [ "multi-user.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.openrgb}/bin/openrgb --server";
        Restart = "on-failure";
      };
    };
  };
}
