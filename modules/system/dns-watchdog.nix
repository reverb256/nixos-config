# DNS Self-Healing Watchdog
# Automatically detects and fixes DNS failures
{
  config,
  pkgs,
  lib,
  ...
}: {
  # DNS health check and auto-recovery service
  systemd.services.dns-watchdog = {
    description = "DNS Health Monitor and Self-Healing";
    wantedBy = ["multi-user.target"];
    after = ["unbound.service" "network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "dns-watchdog" ''
        # DNS Watchdog - Self-healing for DNS failures
        set -euo pipefail

        # Configuration
        DNS_SERVER="127.0.0.1"
        TEST_HOST="cache.nixos.org"
        CHECK_INTERVAL=30
        MAX_RETRIES=3

        # Log function
        log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/dns-watchdog.log
        }

        # Test DNS resolution
        test_dns() {
          # Try to resolve a hostname
          if host "$TEST_HOST" "$DNS_SERVER" &>/dev/null; then
            return 0
          else
            return 1
          fi
        }

        # Check if Unbound is running
        check_unbound() {
          systemctl is-active unbound &>/dev/null
        }

        # Restart Unbound if needed
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

        # Main health check
        if ! test_dns; then
          log "❌ DNS resolution failed for $TEST_HOST"

          # Try restarting Unbound
          if ! check_unbound; then
            log "❌ Unbound is not running - attempting restart..."
            restart_unbound
          else
            log "⚠️  Unbound is running but DNS fails - restarting..."
            restart_unbound
          fi

          # Verify fix
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
      # Run every 5 minutes via timer
    };

    # Don't run continuously - use timer instead
  };

  # Timer for periodic health checks
  systemd.timers.dns-watchdog = {
    description = "DNS Health Monitor Timer";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30s"; # Check 30s after boot
      OnUnitActiveSec = "5min"; # Then every 5 minutes
      AccuracySec = "1s";
    };
  };

  # Ensure log directory exists
  systemd.tmpfiles.rules = [
    "d /var/log 755 root root -"
  ];
}
