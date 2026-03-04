# KDE Plasma 6 Desktop Environment
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Monitor configuration script with TV detection
  monitorSetupScript = pkgs.writeShellApplication {
    name = "plasma-monitor-setup";
    runtimeInputs = with pkgs; [ kscreen ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      LOGFILE="/tmp/plasma-monitor-setup.log"
      echo "=== Monitor setup started at $(date) ===" >> "$LOGFILE"

      # Get connected outputs
      CONNECTED=$(kscreen-doctor -o 2>/dev/null || true)
      [ -z "$CONNECTED" ] && { echo "No outputs detected" >> "$LOGFILE"; exit 0; }

      is_connected() {
          echo "$CONNECTED" | grep -q "Output.*$1.*connected"
      }

      # DP-5: Primary (Priority 1)
      is_connected "DP-5" && kscreen-doctor \
          output.DP-5.enable \
          output.DP-5.mode.71 \
          output.DP-5.geometry.0x349/1920x1080 \
          output.DP-5.scale.1 \
          output.DP-5.priority.1 || true

      # DP-4: Top desk (Priority 2)
      is_connected "DP-4" && kscreen-doctor \
          output.DP-4.enable \
          output.DP-4.mode.44 \
          output.DP-4.geometry.1920x0/1920x1080 \
          output.DP-4.scale.1 \
          output.DP-4.priority.2 || true

      # DP-6: Bottom desk (Priority 3)
      is_connected "DP-6" && kscreen-doctor \
          output.DP-6.enable \
          output.DP-6.mode.91 \
          output.DP-6.geometry.1920x1080/1600x900 \
          output.DP-6.scale.1 \
          output.DP-6.priority.3 || true

      # HDMI-A-2: 4K TV (Priority 4) - only if connected
      if is_connected "HDMI-A-2"; then
          kscreen-doctor \
              output.HDMI-A-2.enable \
              output.HDMI-A-2.mode.1 \
              output.HDMI-A-2.geometry.3520x1080/2560x1440 \
              output.HDMI-A-2.scale.1.5 \
              output.HDMI-A-2.priority.4 || true
          echo "TV configured" >> "$LOGFILE"
      else
          echo "TV not connected, skipping" >> "$LOGFILE"
      fi

      echo "=== Setup completed ===" >> "$LOGFILE"
    '';
  };
in
{
  # Enable the X11 windowing system
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Enable auto-login for j_kro
  services.displayManager.autoLogin = {
    enable = true;
    user = "j_kro";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Qt 6 environment variables to fix RHI/GLES2 issues and KWin stability
  environment.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    QT_USE_RHI_GLES2 = "1";
    QT_QPA_GL_VERSION = "2"; # Force OpenGL 2.0 for better compatibility
    KWIN_DRM_DEVICE = "/dev/dri/card0"; # Prefer primary GPU
    KWIN_DRM_PRIMARY = "1";
  };

  # Make monitor setup script available system-wide
  environment.systemPackages = [ monitorSetupScript ];

  # Systemd user service for automatic monitor configuration
  systemd.user.services.plasma-monitor-setup = {
    description = "Apply monitor configuration on Plasma startup";
    wantedBy = [ "graphical-session.target" ];
    after = [ "plasma-plasmashell.service" "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${monitorSetupScript}/bin/plasma-monitor-setup";
      Restart = "on-failure";
      RestartSec = 2;
      # Wait for display to be ready
      TimeoutStartSec = 10;
    };
  };

  # SDDM login screen configuration
  services.displayManager.sddm.settings = {
    General = {
      # Use KScreen for login screen monitor configuration
      # This ensures consistent behavior between login and desktop
      DisplayServer = "wayland";
    };
    X11 = {
      # Enable KScreen's automatic configuration for X11 fallback
      DisplayServer = "/run/current-system/sw/bin/startplasma-wayland";
    };
  };

  # Auto-start monitor setup via Plasma autostart (fallback method)
  environment.etc."xdg/autostart/plasma-monitor-setup.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Monitor Setup
    Exec=${monitorSetupScript}/bin/plasma-monitor-setup
    X-KDE-autostart-phase=2
    X-KDE-RunCommand-desktop=true
  '';
}
