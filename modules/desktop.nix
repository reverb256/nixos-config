# Desktop Module - Pure Wayland with XWayland Fallback
# Optimized for Steam and gaming with Wayland-first approach
{
  pkgs,
  lib,
  ...
}: {
  # ============================================================================
  # KDE PLASMA 6 (Pure Wayland with XWayland fallback for legacy apps)
  # ============================================================================

  services.desktopManager.plasma6.enable = true;
  # Enable XWayland for backward compatibility with X11 games/apps

  # ============================================================================
  # KDE ESSENTIAL PACKAGES (Steam-compatible)
  # ============================================================================

  environment.systemPackages = with pkgs; [
    # KDE Wayland essentials
    kdePackages.xdg-desktop-portal-kde
    kdePackages.kdbusaddons
    kdePackages.kdeconnect-kde
    kdePackages.plasma-systemmonitor
    kdePackages.kdialog
    kdePackages.kde-cli-tools

    # Network and notifications
    networkmanagerapplet
    libnotify

    # Multimedia support
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
    ffmpeg

    # Gaming utilities
    gamescope
    mangohud
    goverlay

    # Desktop utilities
    firefoxpwa
    btop
    htop
    eza
    bat
    fzf
  ];

  # ============================================================================
  # KDE WALLET
  # ============================================================================

  security.pam.services.sddm.enableKwallet = true;
}
