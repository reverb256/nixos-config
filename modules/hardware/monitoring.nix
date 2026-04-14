{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.monitoring;
in {
  options.hardware.monitoring = {
    enable = lib.mkEnableOption "Hardware monitoring (lm-sensors, fan control)";

    autoDetect = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Run sensors-detect at boot to auto-detect sensor chips";
    };

    fanControl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Enable pwmconfig for manual fan curve control";
    };

    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "nct6775"
        "k10temp"
        "jc42"
      ];
      example = ["nct6775" "k10temp" "jc42" "coretemp"];
      description = "Kernel modules for hardware monitoring chips";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      lm_sensors
      nvtopPackages.full
    ];

    boot.kernelModules = cfg.kernelModules;

    systemd = {
      services = {
        sensors = {
          description = "Load hardware sensor drivers";
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe pkgs.lm_sensors + " -s";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
          };
        };

        sensors-detect = lib.mkIf cfg.autoDetect {
          description = "Auto-detect hardware sensors";
          wantedBy = ["multi-user.target"];
          before = ["sensors.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe pkgs.lm_sensors + " --auto";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            RestrictRealtime = true;
          };
        };

        fancontrol = lib.mkIf cfg.fanControl {
          description = "Fan speed regulator";
          wantedBy = ["multi-user.target"];
          after = ["multi-user.target" "sensors.service"];
          wants = ["sensors.service"];
          serviceConfig = {
            ExecStart = lib.getExe pkgs.python3 + " /etc/nixos/scripts/simple-fancontrol.py";
            Restart = "always";
            RestartSec = "5s";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            RestrictRealtime = true;
          };
        };
      };
    };

    services.udev.extraRules = ''
      ACTION=="add|change", KERNEL=="hwmon*", ATTRS{name}=="nct6775*", SYMLINK+="sensors/fan_controller"

      ACTION=="add|change", KERNEL=="hwmon*", ATTRS{name}=="k10temp", SYMLINK+="sensors/cpu_temp"

      ACTION=="add|change", KERNEL=="hwmon*", ATTRS{name}=="nvme", SYMLINK+="sensors/nvme%n"
    '';

    hardware.sensor.iio.enable = lib.mkDefault true;
  };
}
