{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption types mkIf;
  cfg = config.services.systemd-oomd;
in {
  options.services.systemd-oomd = {
    enable = mkEnableOption "systemd-oomd (userspace OOM killer - understands zswap compression)";
    
    defaultMemoryPressure = mkOption {
      type = types.int;
      default = 15;
      description = "Memory pressure percentage to trigger OOM (0-100, 15 = aggressive, 50 = conservative)";
    };

    defaultMemoryPressureLimit = mkOption {
      type = types.int;
      default = 90;
      description = "Absolute memory pressure limit (0-100, 90 = hard limit)";
    };
  };

  config = mkIf cfg.enable {
    # Disable kernel OOM killer - systemd-oomd replaces it
    boot.kernel.sysctl = {
      "vm.panic_on_oom" = mkForce 0;
    };
    
    systemd = {
      oomd = {
        inherit (lib)
          [ "Monitor-X11"
            "Monitor-2.0"
            "Monitor-X11"
            "Monitor-1.0"
          ];
        # Default action: kill cgroup worst offender in zephyr's case
        # Can be customized per-host if needed
        enabled = true;
        environment = {
          OOMD_MEMORY_PRESSURE = toString cfg.defaultMemoryPressure;
          OOMD_MEMORY_PRESSURE_LIMIT = toString cfg.defaultMemoryPressureLimit;
        };
      };
    };
  };
}