# NixOS config sync — force all hosts to track origin/main
# Every 5 minutes: git fetch + reset --hard origin/main
# This prevents config drift from local changes or stale copies
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.nixos-sync;
  syncScript = pkgs.writeShellScript "nixos-sync" ''
    set -euo pipefail
    FLAKE="/etc/nixos"
    LOG="/var/log/nixos-sync.log"

    if [ ! -d "$FLAKE/.git" ]; then
      echo "$(date -Iseconds) no git repo at $FLAKE" >> "$LOG"
      exit 0
    fi

    cd "$FLAKE"
    BEFORE=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    # Fetch and reset — hard, no mercy
    git fetch origin main 2>> "$LOG"
    git reset --hard origin/main 2>> "$LOG"
    AFTER=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    if [ "$BEFORE" != "$AFTER" ]; then
      echo "$(date -Iseconds) reset $BEFORE -> $AFTER" >> "$LOG"
    fi
  '';
in {
  options.services.nixos-sync = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable NixOS config auto-sync (force git reset to origin/main)";
    };
    interval = mkOption {
      type = types.str;
      default = "5min";
      description = "Sync interval";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.nixos-sync = {
      description = "Sync /etc/nixos to origin/main (force reset)";
      script = "${syncScript}";
      serviceConfig.Type = "oneshot";
    };

    systemd.timers.nixos-sync = {
      description = "Periodic NixOS config sync";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "1min";
      };
    };
  };
}
