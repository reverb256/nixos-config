# Desktop session watchdog — restarts the display manager when the graphical
# session dies but the DM keeps running wedged (no greeter, no session).
#
# Root-cause pair for the 2026-08-14 session teardown on zephyr:
#   dbus-broker fd exhaustion (soft RLIMIT_NOFILE 1024, CVE-2026-16730) killed
#   the user bus -> uwsm wayland-session-bindpid tore down the whole session
#   -> sddm stayed up with neither greeter nor session, leaving the desktop
#   dead for an hour until a manual `systemctl restart display-manager`.
#
# Logic: if the DM is active, no greeter is shown, and no compositor session
# is running for N consecutive checks, restart the DM. A visible greeter means
# the user logged out on purpose — never touch it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.desktop.session-watchdog;
in {
  options.desktop.session-watchdog = {
    enable = lib.mkEnableOption "desktop session watchdog (restart display-manager when wedged)";
    interval = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Check interval in seconds";
    };
    strikes = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Consecutive failed checks before restarting the display manager";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.desktop-session-watchdog = {
      description = "Restart display-manager when the graphical session is wedged";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RuntimeDirectory = "desktop-session-watchdog";
        path = with pkgs; [procps gawk];
        ExecStart = pkgs.writeShellScript "desktop-session-watchdog" ''
          set -euo pipefail
          DM=display-manager.service
          STRIKE_FILE=/run/desktop-session-watchdog/strikes
          MAX=${toString cfg.strikes}
          log() { echo "[desktop-session-watchdog] $1" >&2; }

          # DM down entirely = a different failure mode; out of scope.
          if ! systemctl is-active "$DM" >/dev/null 2>&1; then
            rm -f "$STRIKE_FILE"
            exit 0
          fi

          # Greeter visible = user is at the login screen (expected idle).
          if pgrep -f sddm-greeter >/dev/null 2>&1; then
            rm -f "$STRIKE_FILE"
            exit 0
          fi

          # A graphical session is alive (niri is the compositor here).
          if pgrep -f "niri --session" >/dev/null 2>&1; then
            rm -f "$STRIKE_FILE"
            exit 0
          fi

          # DM active + no greeter + no session = the 2026-08-14 wedge state.
          n=$(( $(cat "$STRIKE_FILE" 2>/dev/null || echo 0) + 1 ))
          echo "$n" > "$STRIKE_FILE"
          log "graphical session absent (strike $n/$MAX); DM active, no greeter"
          if [ "$n" -ge "$MAX" ]; then
            log "restarting $DM"
            systemctl reset-failed "$DM" 2>/dev/null || true
            systemctl restart "$DM"
            rm -f "$STRIKE_FILE"
          fi
        '';
      };
    };

    systemd.timers.desktop-session-watchdog = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "90s";
        OnUnitActiveSec = "${toString cfg.interval}s";
        AccuracySec = "5s";
      };
    };
  };
}
