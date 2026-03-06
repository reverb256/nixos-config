# Corsair Hardware Support Module
# Provides support for Corsair AIO coolers, RGB controllers, and fan controllers
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.corsair;
in {
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
    # Note: corsair-cwi is NOT loaded as it conflicts with liquidctl/OpenRGB
    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "usbhid" # Generic USB HID support
      ];
      description = "Kernel modules for Corsair devices";
    };

    # OpenRGB auto-start service
    autoStartRgb = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-start OpenRGB server at boot (conflicts with liquidctl monitoring)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install Corsair-related packages
    environment.systemPackages = with pkgs;
      [
        liquidctl # Corsair AIO cooler control
        openrgb # OpenRGB for RGB control
      ]
      ++ lib.optionals cfg.rgb.enable [
        openrgb-plugin-effects # OpenRGB effects plugin
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

    # OpenRGB service for auto-start (disabled by default to avoid conflicts with liquidctl)
    systemd.services.openrgb = lib.mkIf (cfg.rgb.enable && cfg.autoStartRgb) {
      description = "OpenRGB RGB lighting control server";
      wantedBy = ["multi-user.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        ExecStart = "${pkgs.openrgb}/bin/openrgb --server";
        Restart = "on-failure";
      };
    };

    # Helper script: AIO status and monitoring
    environment.etc."corsair-status.sh".source = pkgs.writeShellScriptBin "corsair-status" ''
      #!/usr/bin/env bash
      # Corsair AIO and RGB Status

      echo "╔══════════════════════════════════════════════════════════════════╗"
      echo "║              Corsair Device Status                                ║"
      echo "╚══════════════════════════════════════════════════════════════════╝"
      echo ""

      # Color codes
      RED='\033[0;31m'
      YELLOW='\033[1;33m'
      GREEN='\033[0;32m'
      BLUE='\033[0;34m'
      CYAN='\033[0;36m'
      NC='\033[0m'

      if ! command -v liquidctl &> /dev/null; then
          echo -e "''${RED}Error: liquidctl not found!''${NC}"
          exit 1
      fi

      # Check if OpenRGB is running and stop it temporarily
      OPENRGB_RUNNING=false
      if systemctl is-active --quiet openrgb 2>/dev/null; then
          echo -e "''${YELLOW}Stopping OpenRGB service temporarily...''${NC}"
          systemctl stop openrgb
          OPENRGB_RUNNING=true
          sleep 1
      fi

      echo -e "''${CYAN}=== Corsair Devices ===''${NC}"
      liquidctl list
      echo ""

      echo -e "''${CYAN}=== AIO Cooler Status ===''${NC}"
      if liquidctl status &>/dev/null; then
          liquidctl status
      else
          echo "No AIO devices found or unavailable"
      fi
      echo ""

      # Restart OpenRGB if it was running
      if [ "$OPENRGB_RUNNING" = true ]; then
          echo -e "''${CYAN}Restarting OpenRGB service...''${NC}"
          systemctl start openrgb
          echo ""
      fi

      echo -e "''${CYAN}=== Commands ===''${NC}"
      echo "  liquidctl list           - List all Corsair devices"
      echo "  liquidctl status         - Show AIO cooler status"
      echo "  liquidctl initialize     - Initialize all devices"
      echo "  corsair-rgb              - Start OpenRGB GUI"
      echo "  corsair-rgb-server       - Start OpenRGB server mode"
      echo ""
    '';
  };
}
