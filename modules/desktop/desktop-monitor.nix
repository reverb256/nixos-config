# Desktop graphical services (Niri hosts)
#
# gpu-ready, monitor auto-setup and Samsung TV power daemon. These are
# compositor-agnostic: they talk to niri's own IPC (`niri msg`), so zephyr's
# monitor layout and TV power management run inside the niri-uwsm session.
#
# 2026-08-14 rewrite: both scripts were shelling out to kscreen-doctor, but the
# current kscreen build ships no kscreen-doctor binary (only hdrcalibrator),
# and tv-monitor-daemon's unit PATH did not include `niri`, so under
# `set -o pipefail` every run died with "niri: command not found" -> errexit
# -> exit 1, crash-looping every 5s (hundreds of restarts, silent). kscreen is
# gone from runtimeInputs; niri is the compositor and the source of truth.
{
  lib,
  pkgs,
  config,
  ...
}: let
  # The niri binary used for `niri msg` IPC (the HDR fork on zephyr; resolved
  # per-host so the scripts always talk to the compositor actually running).
  # Resolves to nixpkgs niri on hosts without the programs.niri module.
  niriPkg = if (config ? programs.niri) then config.programs.niri.package else pkgs.niri;
  monitorSetupScript = pkgs.writeShellApplication {
    name = "niri-monitor-setup";
    runtimeInputs = [
      niriPkg
      pkgs.libnotify
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
      # Snapshot of connected outputs from niri (the compositor is the source
      # of truth; `niri msg outputs` lists only connected outputs).
      CONNECTED=$(niri msg outputs 2>/dev/null || true)
      [ -z "$CONNECTED" ] && { log "No outputs detected"; exit 0; }
      PREVIOUS_FILE="$STATE_DIR/monitors-previous"
      PREVIOUS_CONNECTED=""
      [ -f "$PREVIOUS_FILE" ] && PREVIOUS_CONNECTED=$(cat "$PREVIOUS_FILE")
      # Resolve the CURRENT connector for a monitor EDID identity. Connector
      # names (DP-2/DP-1/DP-3/HDMI-A-1) renumber when the secondary GPU is
      # VFIO-toggled; identities are stable, so lookup the live connector
      # each run from niri msg outputs.
      resolve_connector() {
          niri msg outputs 2>/dev/null | grep -F "Output \"$1\"" | sed -E 's/.*\(([^)]*)\)/\1/' | head -1
      }
      ZOWIE=$(resolve_connector "PNP(BNQ) ZOWIE RL LCD 9BG06022SL0")
      ASUS=$(resolve_connector "ASUSTek COMPUTER INC ASUS VT229 KBLMTF011991")
      ACER=$(resolve_connector "Acer Technologies X203H LEV0C0254011")
      SAMSUNG=$(resolve_connector "Samsung Electric Company SAMSUNG 0x01000E00")
      was_connected() {
          echo "$PREVIOUS_CONNECTED" | grep -q "$1"
      }
      # Presence in `niri msg outputs` == connected. niri's own config.kdl
      # owns mode/position/scale/HDR; we only ensure outputs are enabled.
      for spec in "$ZOWIE|ZOWIE (Primary)" "$ASUS|ASUS (Top)" "$ACER|ACER (Bottom)" "$SAMSUNG|SAMSUNG (TV) HDR enabled"; do
          conn="''${spec%%|*}"
          label="''${spec##*|}"
          if [ -n "$conn" ]; then
              was_connected "$conn" || log "[CONNECTED] $label"
              niri msg output "$conn" on 2>/dev/null || log "WARNING: could not enable $conn"
          fi
      done
      echo "$CONNECTED" > "$PREVIOUS_FILE"
      log "=== Completed ==="
    '';
  };
  # TV Monitor Daemon for automatic TV power management
  tvMonitorDaemon = pkgs.writeShellApplication {
    name = "tv-monitor-daemon";
    runtimeInputs = [
      niriPkg
      pkgs.libnotify
      pkgs.wireplumber
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/tv-monitor-daemon"
      mkdir -p "$STATE_DIR"
      LOGFILE="$STATE_DIR/tv-monitor-daemon.log"
      TV_STATE_FILE="$STATE_DIR/tv-state"
      # Log to the state file AND stderr so journald captures failures (the
      # old silent exit-1 crash-loop was invisible for weeks).
      log() {
          local msg
          msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
          echo "$msg" | tee -a "$LOGFILE" >&2
      }
      notify() {
          notify-send "TV Monitor" "$1" -i video-display 2>/dev/null || true
      }
      # Resolve the CURRENT TV connector from its EDID identity (connector
      # names renumber on GPU VFIO toggles; identity is stable). Presence in
      # `niri msg outputs` means the connector is live. `|| true` keeps a
      # transient niri failure from aborting the loop under `set -e`.
      resolve_tv_output() {
          niri msg outputs 2>/dev/null | grep -F "Output \"Samsung Electric Company SAMSUNG 0x01000E00\"" | sed -E 's/.*\(([^)]*)\)/\1/' | head -1 || true
      }
      # Disable TV output and switch audio away
      disable_tv() {
          log "TV DISABLING: Disabling $HDMI_OUTPUT and switching audio"
          notify "TV turned off - Disabling display and audio"
          niri msg output "$HDMI_OUTPUT" off 2>/dev/null || log "WARNING: niri could not disable $HDMI_OUTPUT"
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
      # Enable TV output — niri re-applies the configured output block
      # (mode/position/scale/HDR) from config.kdl when the output turns on.
      enable_tv() {
          log "TV ENABLING: Enabling $HDMI_OUTPUT"
          notify "TV turned on - Enabling display with HDR"
          niri msg output "$HDMI_OUTPUT" on 2>/dev/null || log "WARNING: niri could not enable $HDMI_OUTPUT"
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
          # Re-resolve the TV connector each iteration: a GPU VFIO toggle
          # can renumber connectors while the daemon is running.
          HDMI_OUTPUT=$(resolve_tv_output || true)
          # No identity match = TV not enumerated; treat as off.
          if [ -z "$HDMI_OUTPUT" ]; then
              CURRENT_STATE="off"
          else
              CURRENT_STATE="on"
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
      # Monitor/TV user services run inside the niri-uwsm session (niri IPC
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
          # to another VT, niri IPC calls can fail.
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
        # Only active on the session's VT (tty1) - prevents niri IPC spam
        # when the user switches to another VT.
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
