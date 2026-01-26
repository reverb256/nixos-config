# Desktop Module - Steam + Wayland Compatible (REPLACES original desktop.nix)
# Enhanced with Steam-specific environment variables and NVIDIA optimizations
{pkgs, ...}: {
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
  # WAYLAND ENVIRONMENT VARIABLES (Steam-compatible)
  # ============================================================================

  environment.sessionVariables = {
    # Wayland preferences
    QT_QPA_PLATFORM = "wayland";
    GDK_BACKEND = "wayland";
    XDG_SESSION_TYPE = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";

    # NVIDIA Wayland support
    WLR_DRM_NO_MODIFIERS = "1";
    NVD_BACKEND = "direct";
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "nvidia";

    # NVIDIA Wayland hardware acceleration (Fixes KDE Plasma fallback issues)
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";

    # Steam-specific variables (Fixes VRChat launch issues)
    STEAM_FRAME_FORCE_CLOSE = "1"; # Fixes Wayland window issues
    STEAM_LINUX_RUNTIME = "1"; # Enables Steam runtime
    STEAM_USE_NVAPI = "1"; # NVIDIA API support
    STEAM_DEBUG = "0"; # Disable debug logging

    # Proton variables for Steam games
    PROTON_USE_WINED3D = "0"; # Use Vulkan instead of OpenGL
    DXVK_ASYNC = "1"; # Async shader compilation
    WINE_FULLSCREEN_FORCE_DESKTOP = "1"; # Fix fullscreen issues

    # NVIDIA-specific Steam optimizations
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
    __GL_SHADER_DISK_CACHE_SIZE = "1073741824";
    __GL_SHADER_DISK_CACHE_PATH = "/tmp/nvidia-shader-cache";

    # Audio stability for Steam
    PULSE_LATENCY_MSEC = "60";
  };

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
  # PIPEWIRE (Wayland-native audio with Steam compatibility)
  # ============================================================================

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

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

  boot.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];

  # ============================================================================
  # KERNEL PARAMETERS FOR NVIDIA WAYLAND (Conservative)
  # ============================================================================

  boot.kernelParams = [
    "nvidia-drm.modeset=1"
    "nvidia-drm.fbdev=1"
  ];
}
