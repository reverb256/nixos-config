# Monitor layout management via kscreen-doctor.
#
# Applies the fixed multi-monitor layout (DP-5 primary, DP-4 top, DP-6
# bottom, HDMI-A-2 4K HDR TV) on login. NOT Plasma-specific: kscreen-doctor
# works under niri too (zephyr's monitor-setup runs in the niri session on
# tty1), so this is gated on desktop-ness (all non-sentry hosts) rather than
# on plasma6.enable — gating on Plasma would silently kill zephyr's monitor
# configuration. Avoids pulling kscreen into headless sentry's closure
# (kscreen -> pyside6 -> qtwebengine/Chromium).
{ pkgs, lib, config, ... }:

let
  monitorSetupScript = pkgs.writeShellApplication {
    name = "plasma-monitor-setup";
    runtimeInputs = with pkgs; [
      kdePackages.kscreen
      libnotify
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/plasma-monitor-setup"
      mkdir -p "$STATE_DIR"
      LOGFILE="$STATE_DIR/plasma-monitor-setup.log"
      NOTIFY_LOG="$STATE_DIR/monitor-events.log"
      log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$NOTIFY_LOG"
          notify-send "Monitor Setup" "$1" -i video-display 2>/dev/null || true
      }
      log "=== Monitor setup started ==="
      CONNECTED=$(kscreen-doctor -o 2>/dev/null || true)
      [ -z "$CONNECTED" ] && { log "No outputs detected"; exit 0; }
      PREVIOUS_FILE="$STATE_DIR/monitors-previous"
      PREVIOUS_CONNECTED=""
      [ -f "$PREVIOUS_FILE" ] && PREVIOUS_CONNECTED=$(cat "$PREVIOUS_FILE")
      is_connected() {
          echo "$CONNECTED" | awk -v output="$1" '
          /^Output:/ { in_output=0 }
          $0 ~ output { in_output=1 }
          /connected/ && in_output { found=1; exit }
          END { exit (found ? 0 : 1) }
          '
      }
      was_connected() {
          echo "$PREVIOUS_CONNECTED" | grep -q "$1"
      }
      CMD_LIST=()
      if is_connected "DP-5"; then
          was_connected "DP-5" || log "[CONNECTED] DP-5 (Primary)"
          CMD_LIST+=("output.DP-5.enable" "output.DP-5.mode.71" "output.DP-5.position.0,349" "output.DP-5.scale.1" "output.DP-5.priority.1")
      else
          was_connected "DP-5" && log "[DISCONNECTED] DP-5 (Primary)"
      fi
      if is_connected "DP-4"; then
          was_connected "DP-4" || log "[CONNECTED] DP-4 (Top)"
          CMD_LIST+=("output.DP-4.enable" "output.DP-4.mode.44" "output.DP-4.position.1920,0" "output.DP-4.scale.1" "output.DP-4.priority.2")
      else
          was_connected "DP-4" && log "[DISCONNECTED] DP-4 (Top)"
      fi
      if is_connected "DP-6"; then
          was_connected "DP-6" || log "[CONNECTED] DP-6 (Bottom)"
          CMD_LIST+=("output.DP-6.enable" "output.DP-6.mode.91" "output.DP-6.position.1920,1080" "output.DP-6.scale.1" "output.DP-6.priority.3")
      else
          was_connected "DP-6" && log "[DISCONNECTED] DP-6 (Bottom)"
      fi
      if is_connected "HDMI-A-2"; then
          was_connected "HDMI-A-2" || log "[CONNECTED] HDMI-A-2 (TV) HDR enabled"
          CMD_LIST+=("output.HDMI-A-2.enable" "output.HDMI-A-2.mode.1" "output.HDMI-A-2.position.3520,1080" "output.HDMI-A-2.scale.1.5" "output.HDMI-A-2.priority.4" "output.HDMI-A-2.hdr.enable" "output.HDMI-A-2.sdr-brightness.900")
      else
          was_connected "HDMI-A-2" && log "[DISCONNECTED] HDMI-A-2 (TV)"
      fi
      if [ ''${#CMD_LIST[@]} -gt 0 ]; then
          log "Applying configuration..."
          if kscreen-doctor "''${CMD_LIST[@]}"; then
              log "SUCCESS"
          else
              log "WARNING: Some settings failed"
          fi
      fi
      echo "$CONNECTED" > "$PREVIOUS_FILE"
      log "=== Completed ==="
    '';
  };
in
lib.mkIf (config.networking.hostName != "sentry") {
  environment.systemPackages = with pkgs; [
    ddcutil
    libnotify
    monitorSetupScript
  ];

  # Disable KScreen backend launcher (kscreen_backend_launcher) — handled by
  # our user-space monitor-setup instead.
  systemd.user.services."kscreen_backend_launcher".enable = false;

  systemd.user.services.plasma-monitor-setup = {
    description = "Apply monitor configuration";
    wantedBy = ["graphical-session.target"];
    after = [
      "plasma-plasmashell.service"
      "graphical-session.target"
    ];
    # Only run when Plasma is the active VT (tty1).
    # When the user switches to niri (tty2), KWin loses DRM master and
    # kscreen-doctor calls fail with "Atomic modeset test failed: Permission denied".
    serviceConfig.ExecCondition = pkgs.writeShellScript "plasma-vt-check" ''
      ACTIVE_TTY=$(cat /sys/class/tty/tty0/active 2>/dev/null || echo tty0)
      [ "$ACTIVE_TTY" = "tty1" ]
    '';
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${monitorSetupScript}/bin/plasma-monitor-setup";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
