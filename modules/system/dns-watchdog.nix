{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.dns-watchdog;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in {
  options.services.dns-watchdog = {
    enable = mkEnableOption "DNS Health Monitor and Self-Healing";

    externalTestHost = mkOption {
      type = types.str;
      default = "cache.nixos.org";
      description = "External hostname to test DNS resolution against";
    };

    localTestHost = mkOption {
      type = types.str;
      default = "hermes.lan";
      description = "Local hostname to test DNS resolution against";
    };

    checkInterval = mkOption {
      type = types.int;
      default = 300;
      description = "Seconds between DNS health checks";
    };

    maxRetries = mkOption {
      type = types.int;
      default = 3;
      description = "Maximum restart attempts";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.dns-watchdog = {
      description = "DNS Health Monitor and Self-Healing";
      wantedBy = ["multi-user.target"];
      after = [
        "unbound.service"
        "network-online.target"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "dns-watchdog" ''
          set -euo pipefail

          DNS_SERVER="127.0.0.1"
          EXTERNAL_HOST="${cfg.externalTestHost}"
          LOCAL_HOST="${cfg.localTestHost}"

          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/dns-watchdog.log
          }

          test_dns() {
            host "$1" "$DNS_SERVER" &>/dev/null
          }

          check_unbound() {
            systemctl is-active unbound &>/dev/null
          }

          restart_unbound() {
            log "WARNING: DNS failure detected - restarting Unbound..."
            systemctl restart unbound
            sleep 5

            if check_unbound; then
              log "OK: Unbound restarted successfully"
              return 0
            else
              log "FAIL: Failed to restart Unbound"
              return 1
            fi
          }

          # Check external DNS resolution
          if ! test_dns "$EXTERNAL_HOST"; then
            log "FAIL: External DNS resolution failed for $EXTERNAL_HOST"

            if ! check_unbound; then
              log "FAIL: Unbound is not running - attempting restart..."
              restart_unbound
            else
              log "WARNING: Unbound is running but external DNS fails - restarting..."
              restart_unbound
            fi

            if test_dns "$EXTERNAL_HOST"; then
              log "OK: External DNS resolution restored"
            else
              log "FAIL: External DNS still broken after recovery attempt"
              exit 1
            fi
          else
            log "OK: External DNS healthy - $EXTERNAL_HOST resolved successfully"
          fi

          # Check local DNS resolution (warning only — stale config, not crashed)
          if ! test_dns "$LOCAL_HOST"; then
            log "WARNING: Local DNS resolution failed for $LOCAL_HOST (external DNS works — likely stale config, not a crash)"
            exit 0
          else
            log "OK: Local DNS healthy - $LOCAL_HOST resolved successfully"
          fi
        '';
      };
    };

    systemd.timers.dns-watchdog = {
      description = "DNS Health Monitor Timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "${toString cfg.checkInterval}s";
        AccuracySec = "1s";
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/log 755 root root -"
    ];
  };
}
