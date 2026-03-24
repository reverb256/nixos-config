# Hardware Monitoring Module
# Provides visibility and control over CPU, motherboard, and fan sensors
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

    # Auto-detect and load kernel modules for common sensor chips
    autoDetect = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Run sensors-detect at boot to auto-detect sensor chips";
    };

    # Enable manual fan control (WARNING: disables BIOS fan control!)
    fanControl = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = "Enable pwmconfig for manual fan curve control";
    };

    # Sensor chip modules to load
    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "nct6775" # Nuvoton NCT6775F (MSI X570 Tomahawk)
        "k10temp" # AMD CPU temperature
        "jc42" # SMBus temperature sensors
      ];
      example = ["nct6775" "k10temp" "jc42" "coretemp"];
      description = "Kernel modules for hardware monitoring chips";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install hardware monitoring packages
    # nvtopPackages.full supports all GPU types (NVIDIA, AMD, Intel)
    # Ideal for mixed-GPU hosts like Forge, works on single-vendor hosts too
    environment.systemPackages = with pkgs; [
      lm_sensors
      nvtopPackages.full
    ];

    # Load hardware monitoring kernel modules
    boot.kernelModules = cfg.kernelModules;

    # Systemd services for hardware monitoring
    systemd = {
      services = {
        # Base lm-sensors service
        sensors = {
          description = "Load hardware sensor drivers";
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Only load modules, don't run sensors-detect automatically
            # (it can be slow and detects everything at boot)
            ExecStart = lib.getExe pkgs.lm_sensors + " -s";
            # Security hardening
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
          };
        };

        # Optional: sensors-detect service for auto-detection
        sensors-detect = lib.mkIf cfg.autoDetect {
          description = "Auto-detect hardware sensors";
          wantedBy = ["multi-user.target"];
          before = ["sensors.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Run sensors-detect in auto-mode and load detected modules
            ExecStart = lib.getExe pkgs.lm_sensors + " --auto";
            # Security hardening
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            RestrictRealtime = true;
          };
        };

        # Optional: fancontrol service for automatic fan curve management
        fancontrol = lib.mkIf cfg.fanControl {
          description = "Fan speed regulator";
          wantedBy = ["multi-user.target"];
          after = ["multi-user.target" "sensors.service"];
          wants = ["sensors.service"];
          serviceConfig = {
            ExecStart = lib.getExe pkgs.python3 + " /etc/nixos/scripts/simple-fancontrol.py";
            Restart = "always";
            RestartSec = "5s";
            # Custom fancontrol script handles PWM directly
            # Security hardening
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            RestrictRealtime = true;
          };
        };
      };
    };

    # udev rules for consistent hwmon device naming
    services.udev.extraRules = ''
      # Create symlinks for easier sensor access
      # NCT6775 fan controller (MSI X570 Tomahawk)
      ACTION=="add|change", KERNEL=="hwmon*", ATTRS{name}=="nct6775*", SYMLINK+="sensors/fan_controller"

      # AMD CPU temperature
      ACTION=="add|change", KERNEL=="hwmon*", ATTRS{name}=="k10temp", SYMLINK+="sensors/cpu_temp"

      # NVMe drives
      ACTION=="add|change", KERNEL=="hwmon*", ATTRS{name}=="nvme", SYMLINK+="sensors/nvme%n"
    '';

    # Set permissions for sensor access (optional, for non-root users)
    hardware.sensor.iio.enable = lib.mkDefault true;
  };
}
