# Unified RGB Control Module
# Combines OpenRGB + liquidctl + ckb-next + OpenRazer/Polychromatic

{lib, config, pkgs, ...}:
with lib; let
  cfg = config.hardware.unified-rgb;
in {
  options.hardware.unified-rgb = {
    enable = lib.mkEnableOption "Unified RGB control - manages all RGB devices from one interface";

    openrgb = {
      enable = lib.mkEnableOption "OpenRGB daemon for motherboard/GPU/RAM control";
      server = {
        enable = lib.mkEnableOption "Enable OpenRGB server on port 6742";
        port = lib.mkOption {
          type = types.port;
          default = 6742;
          description = "OpenRGB server port for remote control";
        };
        autoStart = lib.mkEnableOption "Auto-start OpenRGB daemon on boot";
      };
      motherboard = lib.mkOption {
        type = types.str;
        default = null;
        description = "Motherboard RGB controller type (asus, gigabyte, msi, asrock, amd)";
        example = "amd";
      };
    };

    liquidctl = {
      enable = lib.mkEnableOption "liquidctl for AIO coolers and Corsair Vengeance RAM";
    };

    profiles = lib.mkOption {
      type = types.attrsOf (types.str);
      default = {};
      description = "RGB profiles for different scenarios (gaming, movie, off)";
      example = {
        gaming = "color=ff00ff mode=breathing";
        movie = "color=00ff00 mode=static";
        off = "color=000000";
      };
    };

    sync = {
      enable = lib.mkEnableOption "Enable RGB synchronization across all devices";
      color = lib.mkOption {
        type = types.str;
        default = "ff00ff";
        description = "Synchronization color (hex format: RRGGBB)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # OpenRGB and liquidctl packages
    environment.systemPackages = with pkgs; [
      openrgb
      (lib.optionalString cfg.openrgb.motherboard "openrgb-with-plugins")
    ] ++ lib.optionals cfg.liquidctl.enable [
      pkgs.liquidctl
    ];

    # OpenRGB udev rules for device access (comprehensive)
    services.udev.extraRules = lib.mkIf cfg.openrgb.enable ''
      # Motherboard SMBus controllers (ASUS, MSI, Gigabyte, ASRock)
      SUBSYSTEM=="i2c-dev", KERNEL=="i2c-*", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="smbus", MODE="0666", GROUP="plugdev"

      # ASUS Aura devices
      SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", ATTR{idProduct}=="*", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", ATTR{idProduct}=="19af", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", ATTR{idProduct}=="1aa6", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0b05", ATTR{idProduct}=="1bed", MODE="0666", GROUP="plugdev"

      # Gigabyte RGB Fusion
      SUBSYSTEM=="usb", ATTR{idVendor}=="0414", MODE="0666", GROUP="plugdev"

      # MSI Mystic Light
      SUBSYSTEM=="usb", ATTR{idVendor}=="1462", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="1462", ATTR{idProduct}=="7b12", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="1462", ATTR{idProduct}=="7b16", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="1462", ATTR{idProduct}=="7b18", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="1462", ATTR{idProduct}=="7b50", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="1462", ATTR{idProduct}=="7b85", MODE="0666", GROUP="plugdev"
      SUBSYSTEM=="usb", ATTR{idVendor}=="1462", ATTR{idProduct}=="7b93", MODE="0666", GROUP="plugdev"

      # ASRock Polychrome
      SUBSYSTEM=="usb", ATTR{idVendor}=="26ce", MODE="0666", GROUP="plugdev"

      # USB RGB controllers
      SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="0c0b", MODE="0666", GROUP="plugdev"  # Corsair Lighting Node
      SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="0c13", MODE="0666", GROUP="plugdev"  # Corsair H115i
      SUBSYSTEM=="usb", ATTR{idVendor}=="1cc4", MODE="0666", GROUP="plugdev"  # Corsair
      SUBSYSTEM=="usb", ATTR{idVendor}=="0951", MODE="0666", GROUP="plugdev"  # Kingston
      SUBSYSTEM=="usb", ATTR{idVendor}=="04d8", MODE="0666", GROUP="plugdev"  # Philips
      SUBSYSTEM=="usb", ATTR{idVendor}=="04ca", MODE="0666", GROUP="plugdev"  # SteelSeries
      SUBSYSTEM=="usb", ATTR{idVendor}=="1d6a", MODE="0666", GROUP="plugdev"  # Razer

      # HID devices
      KERNEL=="hidraw*", ATTRS{idVendor}=="0c09", MODE="0666", GROUP="plugdev"  # ASUS Aura
      KERNEL=="hidraw*", ATTRS{idVendor}=="1b1c", MODE="0666", GROUP="plugdev"  # Corsair/Razer
      KERNEL=="hidraw*", ATTRS{idVendor}=="1cc4", MODE="0666", GROUP="plugdev"  # Corsair
      KERNEL=="hidraw*", ATTRS{idVendor}=="04d8", MODE="0666", GROUP="plugdev"  # Philips
      KERNEL=="hidraw*", ATTRS{idVendor}=="04ca", MODE="0666", GROUP="plugdev"  # SteelSeries
      KERNEL=="hidraw*", ATTRS{idVendor}=="1d6a", MODE="0666", GROUP="plugdev"  # Razer
    '';

    # OpenRGB systemd service with optional server mode
    systemd.services.openrgb-daemon = lib.mkIf cfg.openrgb.enable {
      description = "OpenRGB Daemon - Unified RGB control";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "udev.service"];

      serviceConfig = {
        Type = "simple";
        ExecStart = ''
          ${
            if cfg.openrgb.motherboard != null
              then pkgs.openrgb
              else pkgs.openrgb
          }/bin/openrgb ${
            if cfg.openrgb.motherboard != null then "--motherboard ${cfg.openrgb.motherboard}" else ""
          } ${
            if cfg.openrgb.server.autoStart then "--server" else ""
          } ${
            if cfg.openrgb.server.enable then "--port ${toString cfg.openrgb.server.port}" else ""
          } ${
            if cfg.sync.enable then "--color ${cfg.sync.color}" else ""
          }
        '';
        Restart = "on-failure";
        RestartSec = 10;

        # Allow device access
        DevicePolicy = "auto";
        DeviceAllow = [
          "/dev/bus/usb rwm"
          "/dev/i2c-* rwm"
          "char-hidraw:* rwm"
        ];

        User = "root";
        Group = "root";
        SupplementaryGroups = ["plugdev" "input"];
      };
    };

     # Ensure plugdev group exists
    users.groups.plugdev = {};

    # RGB sync service (optional)
    systemd.services.rgb-sync = lib.mkIf cfg.sync.enable {
      description = "RGB synchronization across all devices";
      wantedBy = ["multi-user.target"];
      after = ["openrgb-daemon.service"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.openrgb}/bin/openrgb --color ${cfg.sync.color}";
        User = "root";
      };
    };
  };
}
