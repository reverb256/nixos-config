# KDE Plasma 6 Desktop Environment
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Monitor configuration script with TV detection
  # NOTE: Full implementation pending - being worked on by another AI
  monitorSetupScript = pkgs.writeShellScript "plasma-monitor-setup" ''
    #!/usr/bin/env bash
    # Placeholder - monitor setup will be implemented by another AI
    exit 0
  '';

  # System-level script that runs before display manager
  bootMonitorScript = pkgs.writeShellScript "boot-monitor-setup" ''
    #!/usr/bin/env bash
    # Placeholder - monitor setup will be implemented by another AI
    exit 0
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
  systemd.services.boot-monitor-setup = {
    description = "Configure monitors at boot before display manager";
    wantedBy = [ "display-manager.service" ];
    before = [ "display-manager.service" "sddm.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = bootMonitorScript;
      RemainAfterExit = true;
      # Wait for DRM devices to be ready
      TimeoutStartSec = 10;
    };
  };

  # ============================================================================
  # USER-LEVEL CONFIGURATION (applies at login)
  # ============================================================================
  systemd.user.services.plasma-monitor-setup = {
    description = "Apply monitor configuration on Plasma startup";
    wantedBy = [ "graphical-session.target" ];
    after = [ "plasma-plasmashell.service" "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${monitorSetupScript}/bin/plasma-monitor-setup";
      Restart = "on-failure";
      RestartSec = 2;
      TimeoutStartSec = 10;
    };
  };

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

  # Udev rules - monitor hotplug is handled by KScreen automatically
  # No custom rules needed - kscreen-doctor handles connected displays gracefully

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
