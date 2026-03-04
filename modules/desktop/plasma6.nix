# KDE Plasma 6 Desktop Environment
{
  config, lib, pkgs, ...
}:
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
in
{
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.autoLogin = { enable = true; user = "j_kro"; };
  services.xserver.xkb = { layout = "us"; variant = ""; };
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

  # Disable KScreen backend launcher
  systemd.user.services."kscreen_backend_launcher".enable = false;

  # Disable KScreen KDED module
  environment.etc."xdg/kdedrc".text = ''
    [Module-kscreen]
    Enabled=false
  '';
  services.displayManager.sddm.settings.General.DisplayServer = "wayland";
  environment.etc."xdg/autostart/plasma-monitor-setup.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Monitor Setup
    Exec=${monitorSetupScript}/bin/plasma-monitor-setup
    X-KDE-autostart-phase=2
    NoDisplay=true
  '';
}
