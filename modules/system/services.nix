# System Services Module
# Systemd services, desktop integration, and Wayland tools from XNM1
{pkgs, ...}: {
  # ============================================================================
  # SYSTEMD PACKAGES
  # ============================================================================
  systemd.packages = with pkgs; [
    auto-cpufreq # CPU frequency scaling
  ];

  # ============================================================================
  # SYSTEM SERVICES
  # ============================================================================
  services = {
    # Power management
    upower.enable = true;

    # D-Bus (message bus)
    dbus = {
      enable = true;
      implementation = "broker";
      packages = with pkgs; [
        xfconf # Xfce configuration system
        gnome2.GConf # GNOME configuration system
      ];
    };

    # Music Player Daemon
    mpd.enable = true;

    # File manager services
    tumbler.enable = true; # Thumbnail generation for Thunar

    # Firmware updates
    fwupd.enable = true;

    # CPU frequency scaling
    # auto-cpufreq.enable = true;  # CONFLICTS with power-profiles-daemon from Plasma
  };

  programs = {
    dconf.enable = true; # Configuration system
    thunar.enable = true;
    xfconf.enable = true;
  };

  # ============================================================================
  # PACKAGES - Desktop & Wayland Tools
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # Browsers
    qutebrowser # Keyboard-driven browser

    # Document viewers
    zathura # PDF viewer

    # Media
    mpv # Media player
    imv # Image viewer

    # Accessibility
    at-spi2-atk # ATK toolkit

    # Qt Wayland integration
    qt6.qtwayland

    # Power and brightness
    psi-notify # Power notifications
    poweralertd # Power alerts

    # Media control
    playerctl # Media player control

    # Process utilities
    psmisc # Process utilities

    # Screenshots & screen recording
    grim # Screenshot utility
    slurp # Screen region selection
    imagemagick # Image manipulation
    swappy # Screenshot annotation
    ffmpeg_6-full # Video processing
    wl-screenrec # Wayland screen recorder

    # Clipboard
    wl-clipboard # Wayland clipboard
    wl-clip-persist # Persistent clipboard
    cliphist # Clipboard history

    # XDG / desktop integration
    xdg-utils

    # Wayland input tools
    wtype # Input emulation
    wlrctl # Wayland control

    # Wayland desktop tools
    waybar # Status bar
    rofi # Application launcher
    dunst # Notification daemon
    avizo # Volume/backlight OSD
    wlogout # Logout menu

    # Graphics
    gifsicle # GIF manipulation
  ];
}
