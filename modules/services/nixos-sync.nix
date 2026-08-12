# NixOS config sync — fast-forward clean remote checkouts
# Every 5 minutes: fetch origin/main and update only clean, non-diverged trees.
# This prevents config drift from local changes or stale copies
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.nixos-sync;
  syncScript = pkgs.writeShellScript "nixos-sync" ''
    set -euo pipefail
    FLAKE="/etc/nixos"
    LOG="/var/log/nixos-sync.log"

    log() {
      echo "$(date -Iseconds) $*" >> "$LOG"
    }

    # The service runs as root, while the checkout is owned by j_kro. Pass the
    # safe-directory exception on every Git invocation instead of relying on a
    # mutable global Git config that may not exist in the service environment.
    git_safe() {
      git -C "$FLAKE" -c safe.directory="$FLAKE" "$@"
    }

    if [ ! -d "$FLAKE/.git" ]; then
      log "no git repo at $FLAKE"
      exit 0
    fi

    BEFORE="$(git_safe rev-parse --short HEAD 2>>"$LOG" || echo "unknown")"
    BRANCH="$(git_safe branch --show-current 2>>"$LOG" || true)"
    if [ "$BRANCH" != "main" ]; then
      log "skip $FLAKE: checkout is not on main (branch=$BRANCH)"
      exit 0
    fi

    STATUS="$(git_safe status --porcelain=v1 --untracked-files=all 2>>"$LOG")" || {
      log "skip $FLAKE: unable to read checkout status"
      exit 1
    }
    if [ -n "$STATUS" ]; then
      log "skip $FLAKE: checkout is dirty at $BEFORE"
      exit 0
    fi

    if ! git_safe fetch origin main 2>>"$LOG"; then
      log "fetch failed for $FLAKE"
      exit 1
    fi

    # Never overwrite local commits or files. A divergent or otherwise
    # non-fast-forward checkout is reported and left for operator review.
    if ! git_safe merge --ff-only origin/main 2>>"$LOG"; then
      log "skip $FLAKE: origin/main is not a fast-forward from $BEFORE"
      exit 0
    fi

    AFTER="$(git_safe rev-parse --short HEAD 2>>"$LOG" || echo "unknown")"
    if [ "$BEFORE" != "$AFTER" ]; then
      log "fast-forwarded $BEFORE -> $AFTER"
    fi
  '';
in {
  options.services.nixos-sync = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable non-destructive NixOS config auto-sync from origin/main";
    };
    interval = mkOption {
      type = types.str;
      default = "5min";
      description = "Sync interval";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.nixos-sync = {
      description = "Fast-forward clean /etc/nixos checkouts to origin/main";
      script = "${syncScript}";
      serviceConfig.Type = "oneshot";
      # The sync script calls `git`, which is absent from systemd's minimal PATH.
      # Provide a full PATH so all Git and logging commands resolve.
      path = [pkgs.git pkgs.coreutils pkgs.findutils pkgs.gnugrep];
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
