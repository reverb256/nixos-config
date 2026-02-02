# Desktop Module - Pure Wayland with XWayland Fallback
# Optimized for Steam and gaming with Wayland-first approach
{pkgs, ...}: {
  # ============================================================================
  # KDE PLASMA 6 (Pure Wayland with XWayland fallback for legacy apps)
  # ============================================================================

  services.desktopManager.plasma6 = {
    enable = true;
    # XWayland is automatically enabled by Plasma 6 for X11 app compatibility
  };

  # ============================================================================
  # XDG DESKTOP PORTAL - DRY configuration for zephyr (KDE + future Hyprland)
  # ============================================================================
  # Portal packages are defined once in extraPortals and referenced where needed.
  # This prevents duplication between portal config and system packages.
  xdg.portal = {
    enable = true;

    # Portal implementations - KDE only (hyprland removed)
    extraPortals = with pkgs; [
      kdePackages.xdg-desktop-portal-kde # Primary for KDE
      xdg-desktop-portal-gtk # GTK app fallback
    ];

    # Desktop-specific portal configurations
    # Use kde section for proper portal selection (creates kde-portals.conf)
    config = {
      kde = {
        default = ["kde" "gtk"];
        "org.freedesktop.impl.portal.FileChooser" = ["kde" "gtk"];
        "org.freedesktop.impl.portal.ScreenCast" = ["kde"];
        "org.freedesktop.impl.portal.Screenshot" = ["kde"];
        "org.freedesktop.impl.portal.RemoteDesktop" = ["kde"];
        "org.freedesktop.impl.portal.Settings" = ["kde" "gtk"];
        "org.freedesktop.impl.portal.Notification" = ["kde"];
        "org.freedesktop.impl.portal.WindowManagement" = ["kde"];
      };
    };

    xdgOpenUsePortal = true;
  };

  # ============================================================================
  # KDE ESSENTIAL PACKAGES (Steam-compatible)
  # ============================================================================

  environment.systemPackages = with pkgs; [
    # KDE Wayland essentials (xdg-desktop-portal-kde is in xdg.portal.extraPortals above - DRY)
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
    pulseaudio # For pactl and PA compatibility tools
    alsa-utils
    alsa-tools
    alsa-firmware
    rtkit # Real-time scheduling for low-latency audio

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
  # PIPEWIRE AUDIO - Modern audio server for Wayland (LOW LATENCY for gaming)
  # ============================================================================
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    
    # Low-latency configuration for gaming (from nix-gaming)
    lowLatency = {
      enable = true;
      quantum = 64;
      rate = 48000;
    };
  };

  # Enable RTKit for real-time audio priority (reduces crackling/latency)
  security.rtkit.enable = true;

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

  # ============================================================================
  # ELECTRON/WAYLAND COMPATIBILITY - Fix electron app crashes
  # ============================================================================
  environment.sessionVariables = {
    # Force XWayland for electron apps that crash on native Wayland
    # This prevents "Failed to connect to Wayland display" errors
    ELECTRON_OZONE_PLATFORM_HINT = "x11";

    # Disable Wayland for problematic electron apps
    NIXOS_OZONE_WL = "1";
  };
}
