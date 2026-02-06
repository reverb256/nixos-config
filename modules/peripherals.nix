{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let cfg = config.hardware.peripherals;
in
{
  options.hardware.peripherals = {
    enable = mkEnableOption "Peripherals support for Corsair devices";

    corsair = {
      enable = mkEnableOption "Corsair device support";
      ckbNext = mkOption {
        type = types.bool;
        default = true;
        description = "Enable ckb-next for Corsair keyboards and mice";
      };
      opencorsairlink = mkOption {
        type = types.bool;
        default = false;
        description = "Enable opencorsairlink for Corsair cooling products";
      };
      openlinkhub = mkOption {
        type = types.bool;
        default = false;
        description = "Enable openlinkhub for Corsair LINK hubs";
      };
    };
  };

  config = mkIf cfg.enable {
    boot.kernelModules = [
      "usbhid"
      "hid-generic"
      "hid-logitech-dj"
    ];

    environment.systemPackages = with pkgs;
      (optionals (cfg.corsair.enable && cfg.corsair.ckbNext) [
        ckb-next
      ]) ++
      (optionals (cfg.corsair.enable && cfg.corsair.opencorsairlink) [
        opencorsairlink
      ]) ++
      (optionals (cfg.corsair.enable && cfg.corsair.openlinkhub) [
        openlinkhub
      ]) ++
      (optionals cfg.corsair.enable [
        headsetcontrol
      ]);

    # ckb-next daemon for Corsair devices
    systemd.services.ckb-next-daemon = mkIf (cfg.corsair.enable && cfg.corsair.ckbNext) {
      description = "ckb-next daemon for Corsair keyboards and mice";
      wantedBy = [ "multi-user.target" ];
      after = [ "syslog.target" "udev.service" ];

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
        SupplementaryGroups = [ "plugdev" "input" ];
      };
    };

    # Configure udev rules for Corsair devices
    # Note: Razer udev rules are handled by hardware.openrazer module
    services.udev.packages =
      (optionals cfg.corsair.enable [
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
      ]);

    # Add plugdev group if not already present
    users.groups.plugdev = {};
  };
}