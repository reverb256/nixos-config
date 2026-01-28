# Desktop Module - Steam + Wayland Compatible (REPLACES original desktop.nix)
# Enhanced with Steam-specific environment variables and NVIDIA optimizations
{pkgs, lib, ...}: {
  # ============================================================================
  # X SERVER (Required for Steam compatibility)
  # ============================================================================

  services.xserver.enable = true;
  services.xserver.videoDrivers = ["nvidia"];

  # ============================================================================
  # SDDM - Wayland with X11 fallback for Steam
  # ============================================================================

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  # Allow fallback to X11 for Steam
  services.displayManager.defaultSession = "plasma";

  # ============================================================================
  # KDE PLASMA 6 (Wayland-native with X11 compatibility)
  # ============================================================================

  services.desktopManager.plasma6.enable = true;

  # ============================================================================
  # AUTO-LOGIN
  # ============================================================================

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";


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

    # Steam and gaming packages
    steam
    steam-run

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

  # ============================================================================
  # NVIDIA MODESETTING
  # ============================================================================

  hardware.nvidia.modesetting.enable = true;

  # ============================================================================
  # KERNEL MODULES FOR DISPLAY
  # ============================================================================

  # ============================================================================
  # KERNEL PARAMETERS FOR NVIDIA WAYLAND (Conservative)
  # ============================================================================

}
