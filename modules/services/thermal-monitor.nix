{ config, lib, pkgs, ... }:

# ============================================================================
# thermal-monitor.nix — read-only CPU thermal watchdog (SPOC, cross-fleet)
#
# Uniform on all AMD nodes (k10temp Tctl/Tdie) and Intel (coretemp
# Package id 0). Emits WARNING/CRITICAL to the journal when the hottest
# CPU temp sensor crosses configurable thresholds. No fan control — that
# lives in each board's BIOS Smart Fan curve. This module is purely
# observability + alerting, so it is safe to deploy everywhere.
#
# Register in modules/default.nix, then flip `services.thermal-monitor.enable`
# on the hosts you want covered.
# ============================================================================

let
  cfg = config.services.thermal-monitor;
  inherit (lib) mkEnableOption mkOption types mkIf;

  # Polls sensors, extracts the first CPU temp reading (AMD Tctl/Tdie or Intel
  # Package id 0), and logs to stderr when thresholds are crossed. Loops forever.
  watchdog = pkgs.writeShellScript "thermal-watchdog" ''
    set -u
    THRESH=${toString cfg.threshold}
    CRIT=${toString cfg.critical}
    INTERVAL=${toString cfg.interval}

    while true; do
      T=$(sensors 2>/dev/null \
            | grep -E 'Tctl:|Tdie:|Package id 0:' \
            | head -1 \
            | grep -oE '[0-9]+\.[0-9]+' \
            | head -1)
      if [ -n "$T" ]; then
        INT=$(printf '%.0f' "$T")
        if [ "$INT" -ge "$CRIT" ]; then
          echo "THERMAL CRITICAL: CPU temp ''${T}C >= critical ''${CRIT}C (TjMax 95C on Zen2/3)" >&2
        elif [ "$INT" -ge "$THRESH" ]; then
          echo "THERMAL WARNING: CPU temp ''${T}C >= threshold ''${THRESH}C" >&2
        fi
      fi
      sleep "$INTERVAL"
    done
  '';
in {
  options.services.thermal-monitor = {
    enable = mkEnableOption "CPU thermal watchdog (read-only monitoring + journal alerts)";
    threshold = mkOption {
      type = types.int;
      default = 90;
      description = "Emit WARNING when hottest CPU sensor reaches this °C.";
    };
    critical = mkOption {
      type = types.int;
      default = 95;
      description = "Emit CRITICAL when hottest CPU sensor reaches this °C (Zen2/3 TjMax).";
    };
    interval = mkOption {
      type = types.int;
      default = 15;
      description = "Poll interval in seconds.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.lm_sensors ];

    systemd.services.thermal-watchdog = {
      description = "CPU thermal watchdog (k10temp/coretemp read-only monitor)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = watchdog;
        Restart = "always";
        RestartSec = 5;
        # Read-only by design: no filesystem writes, no privileges.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        DynamicUser = true;
      };
    };
  };
}
