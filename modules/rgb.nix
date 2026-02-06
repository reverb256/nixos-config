{ pkgs, lib, config, ... }:
with lib;
let cfg = config.hardware.rgb;
in
{
  options.hardware.rgb = {
    enable = mkEnableOption "RGB lighting control support";

    openrgb = {
      enable = mkEnableOption "OpenRGB support for motherboard/GPU RGB";
      withPlugins = mkEnableOption "OpenRGB with all plugins (effects, hardware sync)";
    };

    corsair = {
      enable = mkEnableOption "Corsair RGB via ckb-next";
    };
  };

  config = mkIf cfg.enable {
    # Install RGB packages
    environment.systemPackages = with pkgs; [
      # OpenRGB packages (either with plugins or minimal)
    ] ++ lib.optionals cfg.openrgb.enable (
      if cfg.openrgb.withPlugins then [ openrgb-with-all-plugins ]
      else [ openrgb ]
    ) ++ lib.optionals cfg.corsair.enable [
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

    # OpenRGB systemd service (optional - can run as user)
    systemd.services.openrgb-daemon = mkIf cfg.openrgb.enable {
      description = "OpenRGB Daemon - RGB control for various devices";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "udev.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${if cfg.openrgb.withPlugins then pkgs.openrgb-with-all-plugins else pkgs.openrgb}/bin/OpenRGB --server 6742";
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
        SupplementaryGroups = [ "plugdev" "input" ];
      };
    };

    # Ensure plugdev group exists
    users.groups.plugdev = {};
  };
}
