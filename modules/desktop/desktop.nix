# Desktop Module - Pure Wayland with XWayland Fallback
# Optimized for Steam and gaming with Wayland-first approach
{lib, ...}: {
  # ============================================================================
  # SERVICES - Plasma 6, PipeWire, Bluetooth
  # ============================================================================
  services = {
    # KDE PLASMA 6 (Pure Wayland with XWayland fallback for legacy apps)
    desktopManager.plasma6 = {
      enable = true;
      # XWayland is automatically enabled by Plasma 6 for X11 app compatibility
    };

    # PIPEWIRE AUDIO - Modern audio server for Wayland
    pipewire = {
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
              flags = [
                "ifexists"
                "nofail"
              ];
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

    # PulseAudio disabled - Use PipeWire's PulseAudio replacement
    pulseaudio.enable = false;

    # BLUETOOTH SUPPORT
    blueman.enable = true;
  };

  # ============================================================================
  # HARDWARE - Bluetooth
  # ============================================================================
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # ============================================================================
  # SECURITY - RTKit for real-time audio, PAM limits, KDE wallet
  # ============================================================================
  security = {
    # Enable RTKit for real-time audio
    rtkit.enable = true;

    # PAM limits for real-time audio (RTKit requires RLIMIT_RTPRIO >= rt.prio)
    pam.loginLimits = [
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

    # KDE WALLET
    pam.services.sddm.enableKwallet = true;
  };

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

    # Qt6 Multimedia: Force PipeWire backend and fix library resolution
    # Fixes "qt.multimedia.symbolsresolver: Couldn't load pipewire-0.3 library"
    QT_MEDIA_BACKEND = "pipewire";
    LD_LIBRARY_PATH = lib.mkBefore ["/run/current-system/sw/lib/pipewire-0.3"];
  };
}
