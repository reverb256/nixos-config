# Desktop graphical services (Niri hosts)
#
# gpu-ready, monitor auto-setup and Samsung TV power daemon. These are
# compositor-agnostic: kscreen-doctor works under Niri, so zephyr's monitor
# layout and TV power management run inside the niri-uwsm session.
{
  lib,
  pkgs,
  config,
  ...
}: let
  monitorSetupScript = pkgs.writeShellApplication {
    name = "niri-monitor-setup";
    runtimeInputs = with pkgs; [
      kdePackages.kscreen
      libnotify
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/niri-monitor-setup"
      mkdir -p "$STATE_DIR"
      LOGFILE="$STATE_DIR/niri-monitor-setup.log"
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
      if is_connected "DP-2"; then
          was_connected "DP-2" || log "[CONNECTED] DP-2 (Primary)"
          CMD_LIST+=("output.DP-2.enable" "output.DP-2.mode.71" "output.DP-2.position.0,349" "output.DP-2.scale.1" "output.DP-2.priority.1")
      else
          was_connected "DP-2" && log "[DISCONNECTED] DP-2 (Primary)"
      fi
      if is_connected "DP-1"; then
          was_connected "DP-1" || log "[CONNECTED] DP-1 (Top)"
          CMD_LIST+=("output.DP-1.enable" "output.DP-1.mode.44" "output.DP-1.position.1920,0" "output.DP-1.scale.1" "output.DP-1.priority.2")
      else
          was_connected "DP-1" && log "[DISCONNECTED] DP-1 (Top)"
      fi
      if is_connected "DP-3"; then
          was_connected "DP-3" || log "[CONNECTED] DP-3 (Bottom)"
          CMD_LIST+=("output.DP-3.enable" "output.DP-3.mode.91" "output.DP-3.position.1920,1080" "output.DP-3.scale.1" "output.DP-3.priority.3")
      else
          was_connected "DP-3" && log "[DISCONNECTED] DP-3 (Bottom)"
      fi
      if is_connected "HDMI-A-1"; then
          was_connected "HDMI-A-1" || log "[CONNECTED] HDMI-A-1 (TV) HDR enabled"
          CMD_LIST+=("output.HDMI-A-1.enable" "output.HDMI-A-1.mode.1" "output.HDMI-A-1.position.10000,0" "output.HDMI-A-1.scale.1.5" "output.HDMI-A-1.priority.4" "output.HDMI-A-1.hdr.enable" "output.HDMI-A-1.sdr-brightness.900")
      else
          was_connected "HDMI-A-1" && log "[DISCONNECTED] HDMI-A-1 (TV)"
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
  # TV Monitor Daemon for automatic TV power management
  tvMonitorDaemon = pkgs.writeShellApplication {
    name = "tv-monitor-daemon";
    runtimeInputs = with pkgs; [
      kdePackages.kscreen
      libnotify
      wireplumber
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/tv-monitor-daemon"
      mkdir -p "$STATE_DIR"
      LOGFILE="$STATE_DIR/tv-monitor-daemon.log"
      TV_STATE_FILE="$STATE_DIR/tv-state"
      HDMI_OUTPUT="HDMI-A-1"
      log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
      }
      notify() {
          notify-send "TV Monitor" "$1" -i video-display 2>/dev/null || true
      }
      # Get current TV connection state
      is_tv_connected() {
          kscreen-doctor -o 2>/dev/null | grep -q "$HDMI_OUTPUT.*connected"
      }
      # Get current TV enabled state
      is_tv_enabled() {
          kscreen-doctor -o 2>/dev/null | grep -A 3 "$HDMI_OUTPUT" | grep -q "enabled"
      }
      # Check if TV is actually ON (not just connected)
      # A TV can be connected but in standby/power-save mode
      is_tv_powered_on() {
          # Check if the display is actually accepting signals
          # We'll detect this by seeing if it's in the connected outputs
          is_tv_connected && is_tv_enabled
      }
      # Disable TV output and switch audio away
      disable_tv() {
          log "TV DISABLING: Disabling $HDMI_OUTPUT and switching audio"
          notify "TV turned off - Disabling display and audio"
          # Disable the TV output (atomic, no other displays affected)
          kscreen-doctor "output.$HDMI_OUTPUT.disable" 2>/dev/null || true
          # Move default audio away from HDMI if it was default
          if wpctl status 2>/dev/null | grep -q "Default Sink:.*hdmi"; then
              # Find first non-HDMI audio sink
              local fallback_sink
              fallback_sink=$(wpctl status short 2>/dev/null | grep -v "hdmi" | grep -v "DualSense" | head -1 | awk '{print $1}')
              if [ -n "$fallback_sink" ]; then
                  log "Switching audio from HDMI to: $fallback_sink"
                  wpctl set-default "$fallback_sink" 2>/dev/null || true
              fi
          fi
          echo "disabled" > "$TV_STATE_FILE"
          log "TV disabled successfully"
      }
      # Enable and configure TV output
      enable_tv() {
          log "TV ENABLING: Enabling and configuring $HDMI_OUTPUT"
          notify "TV turned on - Enabling display with HDR"
          # Enable and configure TV with all settings atomically
          kscreen-doctor \
              "output.$HDMI_OUTPUT.enable" \
              "output.$HDMI_OUTPUT.mode.1" \
              "output.$HDMI_OUTPUT.position.3520,1080" \
              "output.$HDMI_OUTPUT.scale.1.5" \
              "output.$HDMI_OUTPUT.priority.4" \
              "output.$HDMI_OUTPUT.hdr.enable" \
              "output.$HDMI_OUTPUT.sdr-brightness.900" \
              2>/dev/null || log "WARNING: TV configuration failed"
          # Note: We DON'T force audio to HDMI - let user choose
          # But we make sure audio isn't stuck on a disconnected sink
          echo "enabled" > "$TV_STATE_FILE"
          log "TV enabled successfully"
      }
      # Main monitoring loop
      log "=== TV Monitor Daemon starting ==="
      # Initialize state
      PREVIOUS_STATE="unknown"
      [ -f "$TV_STATE_FILE" ] && PREVIOUS_STATE=$(cat "$TV_STATE_FILE")
      log "Starting TV state monitoring loop..."
      log "Current TV state: $PREVIOUS_STATE"
      # Monitor interval (seconds) - check every 5 seconds
      CHECK_INTERVAL=5
      while true; do
          # Check if TV is connected AND enabled
          if is_tv_powered_on; then
              CURRENT_STATE="on"
          else
              CURRENT_STATE="off"
          fi
          # State machine
          if [ "$PREVIOUS_STATE" = "on" ] && [ "$CURRENT_STATE" = "off" ]; then
              # TV turned OFF
              disable_tv
              PREVIOUS_STATE="off"
          elif [ "$PREVIOUS_STATE" = "off" ] && [ "$CURRENT_STATE" = "on" ]; then
              # TV turned ON
              enable_tv
              PREVIOUS_STATE="on"
          elif [ "$PREVIOUS_STATE" = "unknown" ]; then
              # First run - set correct state without logging
              if [ "$CURRENT_STATE" = "on" ]; then
                  log "TV detected as ON at startup"
              else
                  log "TV detected as OFF at startup"
              fi
              PREVIOUS_STATE="$CURRENT_STATE"
          fi
          sleep "$CHECK_INTERVAL"
      done
    '';
  };
in {
  config = lib.mkMerge [
    {
      # GPU Readiness Service - Ensures GPU devices are ready before the display
      # manager starts (SDDM autologin into niri-uwsm).
      systemd.services.gpu-ready = {
        description = "Wait for GPU devices to be ready";
        after = ["systemd-modules-load.service"];
        wantedBy = ["display-manager.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "gpu-ready" ''
            # Wait for GPU DRM devices to be ready (NVIDIA/CUDA or AMD/ROCm)
            # NVIDIA: /proc/driver/nvidia, /dev/nvidiactl
            # AMD: /sys/class/drm/card*/device/vendor (0x1002 = AMD)
            log() {
              echo "[gpu-ready] $1" >&2
            }
            # Check if any DRM device exists and is accessible
            check_drm_devices() {
              for dev in /dev/dri/card*; do
                if [ -e "$dev" ] && [ -r "$dev" ]; then
                  return 0
                fi
              done
              return 1
            }
            # Check for NVIDIA GPUs (CUDA)
            has_nvidia() {
              [ -d /proc/driver/nvidia ] && [ -e /dev/nvidiactl ]
            }
            # Check for AMD GPUs (ROCm)
            has_amd() {
              [ -d /sys/class/drm ] && grep -q "0x1002" /sys/class/drm/card*/device/vendor 2>/dev/null
            }
            # Wait for NVIDIA driver to fully load
            wait_nvidia() {
              local max_attempts=30
              for i in $(seq 1 $max_attempts); do
                if [ -e /dev/nvidiactl ] && [ -r /dev/nvidiactl ]; then
                  return 0
                fi
                sleep 0.5
              done
              return 1
            }
            DETECTED_GPUS=""
            has_nvidia && {
              DETECTED_GPUS="$DETECTED_GPUS NVIDIA(CUDA)"
              log "Waiting for NVIDIA driver to fully initialize..."
              wait_nvidia || log "WARNING: NVIDIA driver may not be fully initialized"
            }
            has_amd && DETECTED_GPUS="$DETECTED_GPUS AMD(ROCm)"
            if [ -n "$DETECTED_GPUS" ]; then
              log "Detected GPUs:$DETECTED_GPUS"
            else
              log "No GPUs detected, waiting for DRM devices..."
            fi
            # Wait up to 15 seconds for DRM devices to be accessible
            for i in $(seq 1 75); do
              if check_drm_devices; then
                log "DRM devices ready at /dev/dri/"
                ls -la /dev/dri/card* 2>/dev/null || true
                exit 0
              fi
              sleep 0.2
            done
            # Timeout - log warning but proceed (display manager has restart logic)
            log "WARNING: Timeout waiting for DRM devices, proceeding anyway"
            exit 0
          '';
        };
      };
    }
    (lib.mkIf (config.networking.hostName != "sentry") {
      # Monitor/TV user services run inside the niri-uwsm session (kscreen-doctor
      # works under Niri; zephyr's tv-monitor-daemon runs on tty1). Gated on
      # desktop-ness instead so headless sentry doesn't pull kscreen -> pyside6
      # -> qtwebengine (Chromium) into its closure.
      systemd.user.services = {
        niri-monitor-setup = {
          description = "Apply monitor configuration";
          wantedBy = ["graphical-session.target"];
          after = [
            "graphical-session.target"
          ];
          # Only run when the session's VT is active (tty1). If the user switches
          # to another VT, kscreen-doctor calls fail with
          # "Atomic modeset test failed: Permission denied".
          serviceConfig.ExecCondition = pkgs.writeShellScript "niri-vt-check" ''
            ACTIVE_TTY=$(cat /sys/class/tty/tty0/active 2>/dev/null || echo tty0)
            [ "$ACTIVE_TTY" = "tty1" ]
          '';
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${monitorSetupScript}/bin/niri-monitor-setup";
            Restart = "on-failure";
            RestartSec = 2;
          };
        };
        # Disable KScreen backend launcher
        "kscreen_backend_launcher".enable = false;
        # TV Monitor Daemon - Auto manage TV power state
        # Only active on the session's VT (tty1) - prevents kscreen-doctor
        # spam when the user switches to another VT.
        tv-monitor-daemon = {
          description = "Monitor TV power state and auto-disable/enable";
          wantedBy = ["graphical-session.target"];
          after = [
            "graphical-session.target"
          ];
          serviceConfig.ExecCondition = pkgs.writeShellScript "tv-monitor-vt-check" ''
            ACTIVE_TTY=$(cat /sys/class/tty/tty0/active 2>/dev/null || echo tty0)
            [ "$ACTIVE_TTY" = "tty1" ]
          '';
          serviceConfig = {
            Type = "simple";
            ExecStart = "${tvMonitorDaemon}/bin/tv-monitor-daemon";
            Restart = "always";
            RestartSec = 5;
          };
        };
      };
    })
  ];
}
