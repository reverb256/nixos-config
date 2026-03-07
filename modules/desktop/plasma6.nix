# KDE Plasma 6 Desktop Environment
{ pkgs, ... }:
let
  monitorSetupScript = pkgs.writeShellApplication {
    name = "plasma-monitor-setup";
    runtimeInputs = with pkgs; [ kdePackages.kscreen libnotify ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      LOGFILE="/tmp/plasma-monitor-setup.log"
      NOTIFY_LOG="/tmp/monitor-events.log"

      log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$NOTIFY_LOG"
          notify-send "Monitor Setup" "$1" -i video-display 2>/dev/null || true
      }

      log "=== Monitor setup started ==="
      CONNECTED=$(kscreen-doctor -o 2>/dev/null || true)
      [ -z "$CONNECTED" ] && { log "No outputs detected"; exit 0; }

      PREVIOUS_FILE=/tmp/monitors-previous
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

  bootMonitorScript = pkgs.writeShellScript "boot-monitor-setup" ''
    sleep 2
    ${monitorSetupScript}/bin/plasma-monitor-setup
  '';

  # TV Monitor Daemon for automatic TV power management
  tvMonitorDaemon = pkgs.writeShellApplication {
    name = "tv-monitor-daemon";
    runtimeInputs = with pkgs; [ kdePackages.kscreen libnotify wireplumber ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      LOGFILE="/tmp/tv-monitor-daemon.log"
      TV_STATE_FILE="/tmp/tv-state"
      HDMI_OUTPUT="HDMI-A-2"

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

  # Script to clear stale KDE caches that cause crashes after rebuild
  kdeCacheClearScript = pkgs.writeShellScriptBin "kde-cache-clear" ''
    #!${pkgs.bash}/bin/bash
    # Clear KDE system cache databases that become stale after nixos-rebuild
    # This prevents KSycocaFactory errors and plasmashell crashes

    CACHE_DIRS=(
      "$HOME/.cache/ksycoca5"
      "$HOME/.cache/kwin"
      "$HOME/.cache/kwinrc"
      "$HOME/.cache/khtml"
      "$HOME/.cache/kcookiejar"
      "$HOME/.cache/plasma-sv"
      "$HOME/.cache/ksycoca"
    )

    for dir in "''${CACHE_DIRS[@]}"; do
      if [ -d "$dir" ] || [ -f "$dir" ]; then
        rm -rf "$dir" 2>/dev/null || true
      fi
    done

    # Ensure cache directory structure exists
    mkdir -p "$HOME/.cache"
  '';
in
{
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "j_kro";
  };
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  environment.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    QT_USE_RHI_GLES2 = "1";
    QT_QPA_GL_VERSION = "2";
    KWIN_DRM_DEVICE = "/dev/dri/card0";
    KWIN_DRM_PRIMARY = "1";
  };
  environment.systemPackages = [ monitorSetupScript pkgs.libnotify ];
  systemd.services.boot-monitor-setup = {
    description = "Configure monitors at boot";
    wantedBy = [ "display-manager.service" ];
    before = [ "display-manager.service" "sddm.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = bootMonitorScript;
      RemainAfterExit = true;
      TimeoutStartSec = 10;
    };
  };
  systemd.user.services.plasma-monitor-setup = {
    description = "Apply monitor configuration";
    wantedBy = [ "graphical-session.target" ];
    after = [ "plasma-plasmashell.service" "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${monitorSetupScript}/bin/plasma-monitor-setup";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  environment.etc."xdg/kscreenlockerrc".text = ''
    [General]
    [Screen]
    AutoscreenDisabled=true
    [Daemon]
    AutoConfig=false
  '';
  environment.etc."xdg/kwinrc".text = ''
    [Compositing]
    AllowTearing=false
    GLVSync=true
    AnimationSpeed=3
  '';

  # Window rules for specific applications
  environment.etc."xdg/kwinrulesrc".text = ''
    [General]
    count=1

    # Genshin Impact - Always open on TV (HDMI-A-2)
    [1]
    Description=Genshin Impact - Always on TV (HDMI-A-2)
    wmclass=.*GenshinImpact.*
    wmclassmatch=2
    screen=3
    screenrule=3
    fullscreen=true
    fullscreenrule=3
    types=1
  '';

  # Disable KScreen backend launcher
  systemd.user.services."kscreen_backend_launcher".enable = false;

  # Disable KScreen KDED module
  environment.etc."xdg/kdedrc".text = ''
    [Module-kscreen]
    Enabled=false
  '';

  # ============================================================================
  # KDE CACHE CLEARING - Fix KSycoca crashes after nixos-rebuild
  # ============================================================================

  # User service to clear KDE cache before Plasma starts
  # Runs at boot to prevent crashes after nixos-rebuild
  systemd.user.services.kde-cache-clear = {
    description = "Clear stale KDE cache before Plasma starts";
    wantedBy = [ "graphical-session-pre.target" ];
    before = [ "plasma-plasmashell.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${kdeCacheClearScript}/bin/kde-cache-clear";
      RemainAfterExit = true;
    };
  };

  services.displayManager.sddm.settings.General.DisplayServer = "wayland";

  environment.etc."xdg/autostart/plasma-monitor-setup.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Monitor Setup
    Exec=${monitorSetupScript}/bin/plasma-monitor-setup
    X-KDE-autostart-phase=2
    NoDisplay=true
  '';

  # ============================================================================
  # TV MONITOR DAEMON - Auto manage TV power state
  # ============================================================================

  systemd.user.services.tv-monitor-daemon = {
    description = "Monitor TV power state and auto-disable/enable";
    wantedBy = [ "graphical-session.target" ];
    after = [ "plasma-plasmashellell.service" "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${tvMonitorDaemon}/bin/tv-monitor-daemon";
      Restart = "always";
      RestartSec = 5;
    };
  };

  environment.etc."xdg/autostart/tv-monitor-daemon.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=TV Monitor Daemon
    Exec=${tvMonitorDaemon}/bin/tv-monitor-daemon
    X-KDE-autostart-phase=3
    NoDisplay=true
  '';
}
