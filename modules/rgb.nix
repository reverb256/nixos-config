# RGB Lighting Control Module
# Supports Corsair, Razer, Gigabyte/Aorus, MSI, and EVGA devices via OpenRGB

{ pkgs, lib, config, ... }:
with lib; let
  cfg = config.hardware.rgb;

in {
  options.hardware.rgb = {
    enable = mkEnableOption "RGB lighting control support";

    openrgb = {
      enable = mkEnableOption "OpenRGB support (Corsair, Gigabyte/Aorus, MSI, EVGA)";
      withPlugins = mkEnableOption "OpenRGB with all plugins (effects, hardware sync)";
    };

    corsair = {
      enable = mkEnableOption "Corsair RGB via ckb-next";
      ckbNext = mkOption {
        type = types.bool;
        default = true;
        description = "Enable ckb-next for Corsair keyboards and mice";
      };
    };

    razer = {
      enable = mkEnableOption "Razer RGB via openrazer module";
    };
  };

  config = mkIf cfg.enable {
    # Install RGB packages
    environment.systemPackages = with pkgs;
      lib.optionals cfg.openrgb.enable (
        if cfg.openrgb.withPlugins && pkgs.openrgb-with-plugins or false
        then [pkgs.openrgb-with-plugins]
        else [pkgs.openrgb]
      )
      ++ lib.optionals cfg.corsair.enable [
        ckb-next
      ];

    # OpenRGB udev rules for device access
    services.udev.extraRules = mkIf cfg.openrgb.enable ''
      # OpenRGB device access rules
      SUBSYSTEM=="usb", ATTR{idVendor}=="0c09", ATTR{idProduct}=="0001", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="0c0b", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="0c13", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="1cc4", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0951", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="04d8", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="04ca", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="1d6a", MODE="0666", GROUP="plugdev"
      KERNEL=="hidraw*", ATTRS{idVendor}=="0c09", MODE="0666", GROUP="plugdev"
      KERNEL=="hidraw*", ATTRS{idVendor}=="1b1c", MODE="0666", GROUP="plugdev"
      KERNEL=="hidraw*", ATTRS{idVendor}=="1cc4", MODE="0666", GROUP="plugdev"
    '';

    # OpenRGB systemd service
    systemd.services.openrgb-daemon = mkIf cfg.openrgb.enable {
      description = "OpenRGB Daemon - RGB control for various devices";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "udev.service"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${
          if cfg.openrgb.withPlugins && pkgs.openrgb-with-plugins or false
          then pkgs.openrgb-with-plugins
          else pkgs.openrgb
        }/bin/openrgb --server 6742";
        Restart = "on-failure";
        RestartSec = 10;

        # Allow device access
        DevicePolicy = "auto";
        DeviceAllow = [
          "/dev/bus/usb rwm"
          "char-hidraw:* rwm"
        ];

        User = "root";
        Group = "root";
        SupplementaryGroups = ["plugdev" "input"];
      };
    };

    # Corsair ckb-next daemon
    systemd.services.ckb-next-daemon = mkIf (cfg.corsair.enable && cfg.corsair.ckbNext) {
      description = "ckb-next daemon for Corsair keyboards and mice";
      wantedBy = ["multi-user.target"];
      after = ["syslog.target" "udev.service"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.ckb-next}/bin/ckb-next-daemon";
        Restart = "always";
        RestartSec = 5;

        # Relaxed security for USB device access - udev rules handle permissions
        NoNewPrivileges = false;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictRealtime = true;

        User = "root";
        Group = "root";
        SupplementaryGroups = ["plugdev" "input"];
      };
    };

    # Configure udev rules for Corsair devices
    # Note: Razer udev rules are handled by hardware.openrazer module
    services.udev.packages = lib.mkIf cfg.corsair.enable [
      (pkgs.writeTextDir "etc/udev/rules.d/99-corsair-peripherals.rules" ''
        # Corsair Keyboard and Mouse devices
        SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="*", MODE="0666", GROUP="plugdev"
        KERNEL=="hidraw*", ATTRS{idVendor}=="1b1c", ATTRS{idProduct}=="*", MODE="0666", GROUP="plugdev"

        # Corsair Headset devices
        KERNEL=="hidraw*", ATTRS{idVendor}=="1b1c", ATTRS{idProduct}=="0a1c", MODE="0666", GROUP="plugdev"
        KERNEL=="hidraw*", ATTRS{idVendor}=="1b1c", ATTRS{idProduct}=="0a1d", MODE="0666", GROUP="plugdev"

        # Some older Corsair devices
        KERNEL=="hidraw*", ATTRS{idVendor}=="1b1c", ATTRS{idProduct}=="0a00", MODE="0666", GROUP="plugdev"
        KERNEL=="hidraw*", ATTRS{idVendor}=="1b1c", ATTRS{idProduct}=="0a01", MODE="0666", GROUP="plugdev"
      '')
    ];

    # Ensure plugdev group exists
    users.groups.plugdev = {};
  };
}
