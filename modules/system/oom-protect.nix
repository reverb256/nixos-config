{ config, pkgs, lib, ... }:

# OOM Protection — Mission-Critical Processes
#
# Protects essential processes from the Linux OOM killer by setting
# negative oom_score_adj values. Runs via systemd timer every 30s
# to catch newly spawned processes.
#
# Complements services.earlyoom (in vm-tuning.nix) which handles
# system-wide memory thresholds and kills low-priority processes.

let
  cfg = config.services.oom-protect;

  oomProtectScript = pkgs.writeShellScriptBin "oom-protect" ''
    set -euo pipefail
    SCORE="${toString cfg.oomScore}"
    for pattern in ${lib.concatStringsSep " " cfg.protectedProcesses}; do
      for pid in $(pgrep -f "$pattern" 2>/dev/null || true); do
        CURRENT=$(cat /proc/"$pid"/oom_score_adj 2>/dev/null || echo "")
        if [ "$CURRENT" != "$SCORE" ] && [ -n "$CURRENT" ]; then
          echo "$SCORE" > /proc/"$pid"/oom_score_adj 2>/dev/null || true
        fi
      done
    done
  '';

  # Monitor systemd journal for OOM killer events and log them prominently
  oomMonitorScript = pkgs.writeShellScriptBin "oom-monitor" ''
    set -euo pipefail
    journalctl -kf --no-pager -t kernel --grep="Out of memory" --grep="oom-kill" --grep="Killed process" -o cat 2>/dev/null | while read -r line; do
      echo "[OOM ALERT] $(date '+%Y-%m-%d %H:%M:%S') $line" >> /var/log/oom-events.log
    done
  '';
in
{
  options.services.oom-protect = {
    enable = lib.mkEnableOption "OOM protection for mission-critical processes";

    protectedProcesses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "opencode"
        "hermes"
        "claude"
        "llama-server"
        "llama-cli"
        "llama.cpp"
        "k3s-server"
        "k3s-agent"
        "prometheus"
        "grafana"
        "alloy"
        "postgres"
        "mysql"
        "nix-daemon"
        "sshd"
      ];
      description = "Process patterns to protect from OOM killer";
    };

    oomScore = lib.mkOption {
      type = lib.types.int;
      default = -500;
      description = ''
        OOM score adjustment: -1000 (never kill) to +1000 (always kill first).
        -500 = strongly protected but not immortal.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ oomProtectScript ];

    systemd.services.oom-protect = {
      description = "OOM Protection for mission-critical processes";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${oomProtectScript}/bin/oom-protect";
        ProtectSystem = false;
        PrivateTmp = false;
      };
    };

    systemd.timers.oom-protect = {
      description = "Periodic OOM protection enforcement";
      timerConfig = {
        OnBootSec = "10s";
        OnUnitActiveSec = "30s";
      };
      wantedBy = [ "timers.target" ];
    };

    systemd.services.oom-protect-boot = {
      description = "One-time OOM protection at boot";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${oomProtectScript}/bin/oom-protect";
      };
    };

    # OOM event monitoring — tails kernel journal for OOM killer activity
    systemd.services.oom-monitor = {
      description = "Monitor and log OOM killer events";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${oomMonitorScript}/bin/oom-monitor";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # Ensure log file exists and is rotated
    systemd.tmpfiles.rules = [
      "f /var/log/oom-events.log 0644 root root -"
    ];

    services.logrotate.settings.oom-events = {
      files = "/var/log/oom-events.log";
      frequency = "weekly";
      rotate = 4;
      compress = true;
      missingok = true;
    };
  };
}
