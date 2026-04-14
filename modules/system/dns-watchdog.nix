{
  config,
  pkgs,
  lib,
  ...
}: {
  systemd.services.dns-watchdog = {
    description = "DNS Health Monitor and Self-Healing";
    wantedBy = ["multi-user.target"];
    after = ["unbound.service" "network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "dns-watchdog" ''
        set -euo pipefail

        DNS_SERVER="127.0.0.1"
        TEST_HOST="cache.nixos.org"
        CHECK_INTERVAL=30
        MAX_RETRIES=3

        log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/dns-watchdog.log
        }

        test_dns() {
          if host "$TEST_HOST" "$DNS_SERVER" &>/dev/null; then
            return 0
          else
            return 1
          fi
        }

        check_unbound() {
          systemctl is-active unbound &>/dev/null
        }

        restart_unbound() {
          log "⚠️  DNS failure detected - restarting Unbound..."
          systemctl restart unbound
          sleep 5

          if check_unbound; then
            log "✅ Unbound restarted successfully"
            return 0
          else
            log "❌ Failed to restart Unbound"
            return 1
          fi
        }

        if ! test_dns; then
          log "❌ DNS resolution failed for $TEST_HOST"

          if ! check_unbound; then
            log "❌ Unbound is not running - attempting restart..."
            restart_unbound
          else
            log "⚠️  Unbound is running but DNS fails - restarting..."
            restart_unbound
          fi

          if test_dns; then
            log "✅ DNS resolution restored"
            exit 0
          else
            log "❌ DNS still broken after recovery attempt"
            exit 1
          fi
        else
          log "✅ DNS healthy - $TEST_HOST resolved successfully"
        fi
      '';
    };

  };

  systemd.timers.dns-watchdog = {
    description = "DNS Health Monitor Timer";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "5min";
      AccuracySec = "1s";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log 755 root root -"
  ];
}
