{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkOption types mkIf mkDefault mkForce;
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
        enable = mkDefault true;
        # Passive backstop to earlyoom: act on system-wide swap/memory
        # pressure. earlyoom is the primary (faster-reacting) layer.
        oomdSettings = {
          SwapUsedLimit = 90;
          MemoryUsedLimit = 90;
        };
      };
    };
  };
}