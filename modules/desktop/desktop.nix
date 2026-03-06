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

    # Portal implementations - KDE only
    extraPortals = with pkgs; [
      kdePackages.xdg-desktop-portal-kde # Primary for KDE
      xdg-desktop-portal-gtk # GTK app fallback
    ];

    # Desktop-specific portal configurations
    # Use kde section for proper portal selection (creates kde-portals.conf)
    # This ensures that for each portal type, the system tries kde first, then falls back to gtk
    config = {
      common = {
        # Common defaults for all desktop environments
        default = ["kde" "gtk"];
      };
      kde = {
        # Specific KDE configuration - KDE portals first, GTK as fallback
        default = ["kde" "gtk"];
        # File chooser: prefers KDE (native feel in Dolphin) but falls back to GTK for compatibility
        "org.freedesktop.impl.portal.FileChooser" = ["kde" "gtk"];
        # Screen cast: KDE implementation for better integration with Plasma
        "org.freedesktop.impl.portal.ScreenCast" = ["kde"];
        # Screenshots: KDE implementation for better integration with Spectacle
        "org.freedesktop.impl.portal.Screenshot" = ["kde"];
        # Remote Desktop: KDE implementation for better integration
        "org.freedesktop.impl.portal.RemoteDesktop" = ["kde"];
        # Settings: prefers KDE settings dialogs but falls back to GTK
        "org.freedesktop.impl.portal.Settings" = ["kde" "gtk"];
        # Notifications: KDE implementation for better integration with Plasma
        "org.freedesktop.impl.portal.Notification" = ["kde"];
        # Window management: KDE implementation for better integration with KWin
        "org.freedesktop.impl.portal.WindowManagement" = ["kde"];
        # Additional portal types commonly used
        "org.freedesktop.impl.portal.Print" = ["kde" "gtk"];
        "org.freedesktop.impl.portal.Email" = ["kde" "gtk"];
        "org.freedesktop.impl.portal.Inhibit" = ["kde"];
        "org.freedesktop.impl.portal.Access" = ["kde"];
        "org.freedesktop.impl.portal.Account" = ["kde" "gtk"];
        "org.freedesktop.impl.portal.Background" = ["kde"];
        "org.freedesktop.impl.portal.GameMode" = ["kde"];
        "org.freedesktop.impl.portal.LockScreen" = ["kde"];
        # Realtime: DISABLE GTK portal (has pidns bug) - let PipeWire use RTKit directly
        "org.freedesktop.impl.portal.Realtime" = [];
        "org.freedesktop.impl.portal.NetworkMonitor" = ["kde"];
        "org.freedesktop.impl.portal.ProxyResolver" = ["kde"];
        "org.freedesktop.impl.portal.Trash" = ["kde"];
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
  # PIPEWIRE AUDIO - Modern audio server for Wayland
  # ============================================================================
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;

    # Low latency config - manual config with RTKit-safe rt.prio
    extraConfig = {
      pipewire."99-lowlatency" = {
        "context.properties" = {
          "default.clock.min-quantum" = 256;
          "default.clock.max-quantum" = 2048;
        };
        "context.modules" = [
          {
            name = "libpipewire-module-rt";
            flags = ["ifexists" "nofail"];
            args = {
              "nice.level" = -15;
              "rt.prio" = 19;
              "rt.time.soft" = 200000;
              "rt.time.hard" = 200000;
            };
          }
        ];
      };
      pipewire-pulse."99-lowlatency"."pulse.min.quantum" = "256/48000";
      client."99-lowlatency"."stream.properties"."node.latency" = "256/48000";
    };
  };

  # Enable RTKit for real-time audio
  security.rtkit.enable = true;

  # PAM limits for real-time audio (RTKit requires RLIMIT_RTPRIO >= rt.prio)
  security.pam.loginLimits = [
    {
      domain = "@users";
      item = "rtprio";
      type = "-";
      value = "95";
    }
    {
      domain = "@users";
      item = "memlock";
      type = "-";
      value = "unlimited";
    }
  ];

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

    # GTK apps should use portal for better KDE integration
    GTK_USE_PORTAL = "1";
  };
}
