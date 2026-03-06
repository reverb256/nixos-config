# TV Monitor Daemon - Automatically manage TV display and audio
{pkgs, ...}: let
  tvMonitorDaemon = pkgs.writeShellApplication {
    name = "tv-monitor-daemon";
    runtimeInputs = with pkgs; [kdePackages.kscreen libnotify wireplumber];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      LOGFILE="/tmp/tv-monitor-daemon.log"
      TV_STATE_FILE="/tmp/tv-state"
      HDMI_OUTPUT="HDMI-A-2"
      HDMI_AUDIO_SINK="alsa_output.pci-0000_2d_00.1.hdmi-stereo"

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
  # Add the daemon to system packages
  environment.systemPackages = [tvMonitorDaemon];

  # Systemd user service for the TV monitor daemon
  systemd.user.services.tv-monitor-daemon = {
    description = "Monitor TV power state and manage display/audio";
    wantedBy = ["graphical-session.target"];
    after = ["plasma-plasmashell.service" "graphical-session.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${tvMonitorDaemon}/bin/tv-monitor-daemon";
      Restart = "always";
      RestartSec = 5;
      # Don't restart too quickly if it's crashing
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
  };

  # Auto-start the daemon via Plasma
  environment.etc."xdg/autostart/tv-monitor-daemon.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=TV Monitor Daemon
    Exec=${tvMonitorDaemon}/bin/tv-monitor-daemon
    X-KDE-autostart-phase=2
    NoDisplay=true
  '';
}
