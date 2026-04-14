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

    aio.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Enable Corsair AIO cooler support via liquidctl";
    };

    rgb.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Enable OpenRGB for Corsair RGB control";
    };

    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "usbhid"
      ];
      example = ["usbhid" "corsair-cwi"];
      description = "Kernel modules for Corsair devices";
    };

    autoStartRgb = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Auto-start OpenRGB server at boot (conflicts with liquidctl monitoring)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs;
      [
        liquidctl
        openrgb
      ]
      ++ lib.optionals cfg.rgb.enable [
        openrgb-plugin-effects
      ];

    boot.kernelModules = cfg.kernelModules;

    services.udev.extraRules = ''
      ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="1b38", MODE="0666"

      ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="0c0b", MODE="0666"

      ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", ATTR{idProduct}=="0c13", MODE="0666"

      ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", MODE="0666"

      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1b1c", MODE="0666"
      ACTION=="add|change", KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1b1c", MODE="0666"

      SUBSYSTEM=="usb", ATTR{idVendor}=="1b1c", TAG+="uaccess"
      KERNEL=="hidraw*", ATTRS{idVendor}=="1b1c", TAG+="uaccess"
    '';

    systemd.services.openrgb = lib.mkIf (cfg.rgb.enable && cfg.autoStartRgb) {
      description = "OpenRGB RGB lighting control server";
      wantedBy = ["multi-user.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        ExecStart = lib.getExe pkgs.openrgb + " --server";
        Restart = "on-failure";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET"];
      };
    };

    environment.etc."corsair-status.sh".source = pkgs.writeShellScriptBin "corsair-status" ''
      #!/usr/bin/env bash

      echo "╔══════════════════════════════════════════════════════════════════╗"
      echo "║              Corsair Device Status                                ║"
      echo "╚══════════════════════════════════════════════════════════════════╝"
      echo ""

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
