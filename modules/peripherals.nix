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
    enable = mkEnableOption "Peripherals support for Razer and Corsair devices";
    
    razer = {
      enable = mkEnableOption "Razer device support (OpenRazer)";
      daemon = mkOption {
        type = types.bool;
        default = true;
        description = "Enable the OpenRazer daemon to manage Razer peripherals";
      };
      package = mkOption {
        type = types.package;
        default = pkgs.openrazer-daemon;
        description = "Package to use for OpenRazer daemon";
      };
    };
    
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
    # Enable required kernel modules for USB HID devices
    boot.kernelModules = [
      "usbhid"
      "hid-generic"
      "hid-logitech-dj"  # For Logitech receivers that may work with some gaming peripherals
    ];

    # Razer device support (OpenRazer)
    environment.systemPackages = with pkgs;
      (optionals cfg.razer.enable [
        cfg.razer.package
        razergenie
        polychromatic
        razer-cli
      ]) ++
      (optionals (cfg.corsair.enable && cfg.corsair.ckbNext) [
        ckb-next
      ]) ++
      (optionals (cfg.corsair.enable && cfg.corsair.opencorsairlink) [
        opencorsairlink
      ]) ++
      (optionals (cfg.corsair.enable && cfg.corsair.openlinkhub) [
        openlinkhub
      ]) ++
      # Also add headsetcontrol which supports some Corsair headsets
      (optionals cfg.corsair.enable [
        headsetcontrol
      ]);

    # Enable OpenRazer daemon if requested
    # Properly define the OpenRazer daemon service
    systemd.services.openrazer-daemon = mkIf cfg.razer.daemon {
      description = "OpenRazer daemon for managing Razer peripherals";
      wantedBy = [ "multi-user.target" ];
      after = [ "syslog.target" "udev.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.razer.package}/bin/openrazer-daemon --run-as-root";
        Restart = "always";
        RestartSec = 5;

        # Security settings
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        # Device access for Razer devices
        DevicePolicy = "closed";
        DeviceAllow = [
          "char-hidraw:* rwm"
          "char-usbmon:* r"
          "char-input:event r"
          "char-input/mouse/* r"
          "char-input/js* r"
        ];

        # User running the daemon (should be root to access hardware)
        User = "root";
        Group = "root";

        # Allow the daemon access to DBus which it might need
        SupplementaryGroups = [ "plugdev" "input" ];
      };
    };

    # Configure udev rules for both Razer and Corsair devices
    services.udev.packages =
      (optionals cfg.razer.enable [
        (pkgs.writeTextDir "etc/udev/rules.d/99-razer-peripherals.rules" ''
          # Razer devices udev rules
          KERNEL=="hidraw*", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="0*", MODE="0666", GROUP="plugdev"

          # Allow users in 'plugdev' group to access Razer devices
          SUBSYSTEM=="usb", ATTR{idVendor}=="1532", MODE="0666", GROUP="plugdev"
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1532", MODE="0666", GROUP="plugdev"

          # Additional Razer device IDs
          SUBSYSTEM=="usb", ATTR{idVendor}=="1532", ATTR{idProduct}=="0*", MODE="0666", GROUP="plugdev"
          KERNEL=="hidraw*", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="0*", MODE="0666", GROUP="plugdev"
        '')
      ]) ++
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