# Enhanced Desktop Module - Steam + Wayland Compatible
# Replaces the current desktop.nix for better Steam support
{pkgs, ...}: {

  # ============================================================================
  # X SERVER (Required for Steam compatibility)
  # ============================================================================
  
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];

  # ============================================================================
  # SDDM - Wayland with X11 fallback for Steam
  # ============================================================================
  
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  
  # Allow fallback to X11 for Steam
  services.displayManager.defaultSession = "plasma-wayland";

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
    
    # Desktop utilities
    firefoxpwa
    btop
    htop
    eza
    bat
    fzf
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