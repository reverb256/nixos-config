{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.monitoring;
in {
  options.hardware.monitoring = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Hardware monitoring (lm-sensors, fan control)";
    };

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
        "it87"
        "k10temp"
        "jc42"
      ];
      example = ["nct6775" "k10temp" "jc42" "coretemp"];
      description = "Kernel modules for hardware monitoring chips";
    };

    useIt87Fork = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Use the frankcrawford/it87 out-of-tree fork (IT8686E/IT8792E + MMIO, Gigabyte boards) instead of in-tree it87";
    };

    fanScript = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/nixos/scripts/fancontrol-nexus.py";
      description = "Path to the fan control script (board-specific)";
    };
  };

  config = lib.mkMerge [
    # Assertion fires regardless of enable state
    {
      assertions = [
        {
          assertion =
            cfg.enable
            || (cfg.autoDetect
              && !cfg.fanControl
              && cfg.kernelModules == ["it87" "k10temp" "jc42"]);
          message = "hardware.monitoring: sub-options customized but enable = false. Add `enable = true` or remove the sub-options.";
        }
      ];
    }
    (lib.mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        lm_sensors
        nvtopPackages.full
      ];

      # it87 fork: the cachyos kernelPackages set already exposes `it87`
      # (frankcrawford fork). Compress the module to .ko.xz so it overrides
      # the in-tree copy (fork builds .ko; modprobe picks .ko.xz first).
      # MMIO + ignore_resource_conflict for Gigabyte EC-controlled channels.
      boot.extraModulePackages = lib.mkIf cfg.useIt87Fork [
        (config.boot.kernelPackages.it87.overrideAttrs (super: {
          postInstall = (super.postInstall or "") + ''
            find $out -name '*.ko' -exec xz {} \;
          '';
        }))
      ];
      # Disable the IN-TREE it87 so it doesn't collide with the fork's module
      # at the same path (buildEnv/modules-shrunk would otherwise reject or
      # shadow it). Rebuilding the kernel with SENSORS_IT87=no is the
      # documented way to let the out-of-tree fork own the module name.
      boot.kernelPatches = lib.mkIf cfg.useIt87Fork [
        {
          name = "disable-in-tree-it87";
          patch = null;
          extraStructuredConfig = with lib.kernel; {
            SENSORS_IT87 = lib.mkForce no;
          };
        }
      ];
      boot.kernelModules = cfg.kernelModules;
      boot.extraModprobeConfig = lib.mkIf cfg.useIt87Fork ''
        options it87 mmio=on ignore_resource_conflict=1
      '';
      boot.kernelParams = lib.mkIf cfg.useIt87Fork [
        "acpi_enforce_resources=lax"
      ];

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
              ExecStart = lib.getExe pkgs.python3 + " ${cfg.fanScript}";
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
        ACTION=="add|change", KERNEL=="hwmon*", ATTRS{name}=="it87*", SYMLINK+="sensors/fan_controller"
        ACTION=="add|change", KERNEL=="hwmon*", ATTRS{name}=="it8792", SYMLINK+="sensors/fan_controller_ec"
        ACTION=="add|change", KERNEL=="hwmon*", ATTRS{name}=="k10temp", SYMLINK+="sensors/cpu_temp"
        ACTION=="add|change", KERNEL=="hwmon*", ATTRS{name}=="nvme", SYMLINK+="sensors/nvme%n"
      '';

      hardware.sensor.iio.enable = lib.mkDefault true;
    })
  ];
}
