# KDE Plasma 6 Desktop Environment
{
  config, lib, pkgs, ...
}:
let
  monitorSetupScript = pkgs.writeShellApplication {
    name = "plasma-monitor-setup";
    runtimeInputs = with pkgs; [ kdePackages.kscreen ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      LOGFILE="/tmp/plasma-monitor-setup.log"
      echo "=== Monitor setup at $(date) ===" >> "$LOGFILE"
      CONNECTED=$(kscreen-doctor -o 2>/dev/null || true)
      [ -z "$CONNECTED" ] && { echo "No outputs" >> "$LOGFILE"; exit 0; }
      is_connected() {
          echo "$CONNECTED" | awk -v output="$1" '
          /^Output:/ { in_output=0 }
          $0 ~ output { in_output=1 }
          /connected/ && in_output { found=1; exit }
          END { exit (found ? 0 : 1) }
          '
      }
      CMD_LIST=()
      is_connected "DP-5" && CMD_LIST+=("output.DP-5.enable" "output.DP-5.mode.71" "output.DP-5.position.0,349" "output.DP-5.scale.1" "output.DP-5.priority.1")
      is_connected "DP-4" && CMD_LIST+=("output.DP-4.enable" "output.DP-4.mode.44" "output.DP-4.position.1920,0" "output.DP-4.scale.1" "output.DP-4.priority.2")
      is_connected "DP-6" && CMD_LIST+=("output.DP-6.enable" "output.DP-6.mode.91" "output.DP-6.position.1920,1080" "output.DP-6.scale.1" "output.DP-6.priority.3")
      if is_connected "HDMI-A-2"; then
          CMD_LIST+=("output.HDMI-A-2.enable" "output.HDMI-A-2.mode.1" "output.HDMI-A-2.position.3520,1080" "output.HDMI-A-2.scale.1.5" "output.HDMI-A-2.priority.4" "output.HDMI-A-2.hdr.enable" "output.HDMI-A-2.sdr-brightness.900")
      fi
      [ ''${#CMD_LIST[@]} -gt 0 ] && kscreen-doctor "''${CMD_LIST[@]}" || true
      echo "=== Done ===" >> "$LOGFILE"
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
  environment.systemPackages = [ monitorSetupScript ];
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
  '';
  environment.etc."xdg/kwinrc".text = ''
    [Compositing]
    AllowTearing=false
    GLVSync=true
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
