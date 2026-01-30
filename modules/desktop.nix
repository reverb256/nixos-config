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

    # Audio utilities and tools
    pipewire
    wireplumber
    pavucontrol
    pulsemixer
    pulseaudio  # For pactl and PA compatibility tools
    alsa-utils
    alsa-tools
    alsa-firmware
    rkit  # Real-time scheduling for low-latency audio

    # Bluetooth tools
    bluez
    bluez-tools

    # Gaming utilities
    gamescope
    mangohud
    goverlay

    # Desktop utilities
    # firefoxpwa  # MOVED to home.nix - requires Firefox compilation
    btop
    htop
    eza
    bat
    fzf
  ];

  # ============================================================================
  # PIPEWIRE AUDIO - Modern audio server for Wayland
  # ============================================================================
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Enable RTKit for real-time audio priority (reduces crackling/latency)
  services.rtkit.enable = true;

  # ============================================================================
  # BLUETOOTH SUPPORT
  # ============================================================================
  services.blueman.enable = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Bluetooth audio profiles support
  services.pulseaudio.enable = false; # Use PipeWire's PulseAudio replacement

  # ============================================================================
  # KDE WALLET
  # ============================================================================

  security.pam.services.sddm.enableKwallet = true;
}
