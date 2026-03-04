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

      # Build command list for atomic application (prevents flashing!)
      CMD_LIST=()

      # DP-5: Primary (Priority 1)
      if is_connected "DP-5"; then
          echo "Configuring DP-5 (Primary)" >> "$LOGFILE"
          CMD_LIST+=("output.DP-5.enable" "output.DP-5.mode.71" "output.DP-5.geometry.0x349/1920x1080" "output.DP-5.scale.1" "output.DP-5.priority.1")
      fi

      # DP-4: Top desk (Priority 2)
      if is_connected "DP-4"; then
          echo "Configuring DP-4" >> "$LOGFILE"
          CMD_LIST+=("output.DP-4.enable" "output.DP-4.mode.44" "output.DP-4.geometry.1920x0/1920x1080" "output.DP-4.scale.1" "output.DP-4.priority.2")
      fi

      # DP-6: Bottom desk (Priority 3)
      if is_connected "DP-6"; then
          echo "Configuring DP-6" >> "$LOGFILE"
          CMD_LIST+=("output.DP-6.enable" "output.DP-6.mode.91" "output.DP-6.geometry.1920x1080/1600x900" "output.DP-6.scale.1" "output.DP-6.priority.3")
      fi

      # HDMI-A-2: 4K TV (Priority 4) - only if connected
      if is_connected "HDMI-A-2"; then
          echo "Configuring HDMI-A-2 (TV)" >> "$LOGFILE"
          CMD_LIST+=("output.HDMI-A-2.enable" "output.HDMI-A-2.mode.1" "output.HDMI-A-2.geometry.3520x1080/2560x1440" "output.HDMI-A-2.scale.1.5" "output.HDMI-A-2.priority.4" "output.HDMI-A-2.hdr.enable" "output.HDMI-A-2.sdr-brightness.900")
      else
          echo "TV not connected, skipping" >> "$LOGFILE"
      fi

      # Apply all changes atomically in one command (prevents multiple refreshes!)
      if [ ''${#CMD_LIST[@]} -gt 0 ]; then
          echo "Applying configuration atomically..." >> "$LOGFILE"
          kscreen-doctor "''${CMD_LIST[@]}" || echo "Warning: Some settings may not have applied" >> "$LOGFILE"
      fi

      echo "=== Setup completed ===" >> "$LOGFILE"
    '';
  };

  # System-level script that runs before display manager
  bootMonitorScript = pkgs.writeShellScript "boot-monitor-setup" ''
    #!/usr/bin/env bash
    # Run monitor setup at boot before display manager
    # This ensures monitors are configured from the start

    sleep 2  # Wait for displays to be ready

    if [ -x /run/current-system/sw/bin/kscreen-doctor ]; then
      ${monitorSetupScript}/bin/plasma-monitor-setup
    fi
  '';
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

  # ============================================================================
  # BOOT-LEVEL CONFIGURATION (applies before display manager)
  # ============================================================================
  # Temporarily disabled due to build error - another AI is fixing it
  # systemd.services.boot-monitor-setup = {
  #   description = "Configure monitors at boot before display manager";
  #   wantedBy = [ "display-manager.service" ];
  #   before = [ "display-manager.service" "sddm.service" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = bootMonitorScript;
  #     RemainAfterExit = true;
  #     # Wait for DRM devices to be ready
  #     TimeoutStartSec = 10;
  #   };
  # };

  # ============================================================================
  # USER-LEVEL CONFIGURATION (applies at login)
  # ============================================================================
  # Temporarily disabled due to build error - another AI is fixing it
  # systemd.user.services.plasma-monitor-setup = {
  #   description = "Apply monitor configuration on Plasma startup";
  #   wantedBy = [ "graphical-session.target" ];
  #   after = [ "plasma-plasmashell.service" "graphical-session.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${monitorSetupScript}/bin/plasma-monitor-setup";
  #     Restart = "on-failure";
  #     RestartSec = 2;
  #     TimeoutStartSec = 10;
  #   };
  # };

  # ============================================================================
  # PREVENT FLASHING ON HOTPLUG
  # ============================================================================
  # Disable KScreen's automatic reconfiguration to prevent flashing
  environment.etc."xdg/kscreenlockerrc".text = ''
    [General]
    # Prevent KScreen from auto-reconfiguring on hotplug
    [Screen]
    # Disable automatic screen configuration
    AutoscreenDisabled=true
  '';

  # KWin configuration to prevent screen redraws
  environment.etc."xdg/kwinrc".text = ''
    [Compositing]
    # Prevent compositing resets on display changes
    AllowTearing=false
    AnimationSpeed=3
    Backend=OpenGL
    GLPreferBufferSwap=a
    GLVSync=true
    LatencyPolicy=ExtremelyLowLatency
    # Prevent screen refresh on hotplug
    UnredirectFullscreenWindows=false
    WindowsBlockCompositing=false

    [Effect-windowview]
    # Smooth transitions
    BorderActivate=9

    [ElectricBorders]
    # Prevent accidental edge triggers
    TilingEnabled=true
    Top=None
    TopRight=None
    Right=None
    BottomRight=None
    Bottom=None
    BottomLeft=None
    Left=None
    TopLeft=None
  '';

  # Udev rule to handle monitor hotplug gracefully
  services.udev.extraRules = ''
    # Handle monitor hotplug events gracefully
    ACTION=="change", SUBSYSTEM=="drm", ENV{HOTPLUG}=="1", RUN+="/run/current-system/sw/bin/logger -t monitor-hotplug 'Display hotplug detected'"
  '';

  # ============================================================================
  # SDDM LOGIN SCREEN CONFIGURATION
  # ============================================================================
  services.displayManager.sddm.settings = {
    General = {
      DisplayServer = "wayland";
      # Use KScreen for login screen monitor configuration
      # This ensures consistent behavior between login and desktop
    };
    X11 = {
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
    NoDisplay=true
  '';

  # ============================================================================
  # KERNEL PARAMETERS FOR BETTER DISPLAY HANDLING
  # ============================================================================
  boot.kernelParams = [
    # Disable display hotplug detection to prevent flashing
    # "video=HDMI-A-1:D"  # Uncomment if TV is on HDMI-A-1 and you want to disable it at boot
    # Or use "nomodeset" as last resort (not recommended)
  ];
}
