# Desktop Module - KDE Plasma 6 with Wayland ONLY
# All hosts get the same desktop environment
{pkgs, ...}: {
  # ============================================================================
  # X SERVER (Required for display, but we force Wayland)
  # ============================================================================

  services.xserver.enable = true;

  # ============================================================================
  # SDDM - Wayland ONLY (No X11 fallback)
  # ============================================================================

  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  # ============================================================================
  # KDE PLASMA 6 (Wayland-native)
  # ============================================================================

  services.desktopManager.plasma6.enable = true;

  # ============================================================================
  # AUTO-LOGIN (Same on all hosts for consistency)
  # ============================================================================

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "j_kro";

  # ============================================================================
  # WAYLAND ENVIRONMENT VARIABLES (FORCE Wayland everywhere)
  # ============================================================================

  environment.sessionVariables = {
    # Force Qt to use Wayland
    QT_QPA_PLATFORM = "wayland";
    # Force GTK to use Wayland
    GDK_BACKEND = "wayland";
    # Force session type
    XDG_SESSION_TYPE = "wayland";
    # Qt Wayland decorations
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    # Disable X11 apps trying to use X
    # (they will fail gracefully or use xwayland)
  };

  # ============================================================================
  # KDE ESSENTIAL PACKAGES (Wayland-compatible)
  # ============================================================================

  environment.systemPackages = with pkgs; [
    # KDE Wayland essentials
    kdePackages.xdg-desktop-portal-kde # Essential for window tracking in Wayland
    kdePackages.kdbusaddons # DBus integration
    kdePackages.kdeconnect-kde # Device integration
    kdePackages.plasma-systemmonitor # System monitoring
    kdePackages.kdialog # KDE dialogs
    kdePackages.kde-cli-tools # KDE command line tools

    # Network tray (works in Wayland)
    networkmanagerapplet

    # Desktop notifications
    libnotify

    # Multimedia support (PipeWire, Wayland-native)
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
    ffmpeg
    yt-dlp

    # Desktop utilities
    firefoxpwa # Progressive Web Apps
    btop # System monitor
    htop
    eza # Modern ls
    bat # Modern cat
    fzf # Fuzzy finder

    # Fonts are in base.nix
  ];

  # ============================================================================
  # PIPEWIRE (Wayland-native audio)
  # ============================================================================

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # ============================================================================
  # KDE WALLET (for automatic unlocking in SDDM)
  # ============================================================================

  security.pam.services.sddm.enableKwallet = true;

  # ============================================================================
  # NVIDIA MODESETTING (Required for Wayland on NVIDIA)
  # ============================================================================

  hardware.nvidia.modesetting.enable = true;

  # ============================================================================
  # KERNEL MODULES FOR DISPLAY
  # ============================================================================

  boot.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];

  # ============================================================================
  # KERNEL PARAMETERS FOR NVIDIA WAYLAND
  # ============================================================================

  boot.kernelParams = [
    "nvidia-drm.modeset=1"
    "nvidia-drm.fbdev=1"
  ];
}
