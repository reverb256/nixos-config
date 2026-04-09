# Desktop Module - Pure Wayland with XWayland Fallback
# Optimized for Steam and gaming with Wayland-first approach
{
  pkgs,
  lib,
  ...
}:
let
  # Monitor Setup Script - Auto-configures displays based on what's connected
  monitorSetupScript = pkgs.writeShellApplication {
    name = "plasma-monitor-setup";
    runtimeInputs = with pkgs; [
      kdePackages.kscreen
      libnotify
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      LOGFILE="/tmp/plasma-monitor-setup.log"
      NOTIFY_LOG="/tmp/monitor-events.log"

      log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$NOTIFY_LOG"
          notify-send "Monitor Setup" "$1" -i video-display 2>/dev/null || true
      }

      log "=== Monitor setup started ==="
      CONNECTED=$(kscreen-doctor -o 2>/dev/null || true)
      [ -z "$CONNECTED" ] && { log "No outputs detected"; exit 0; }

      PREVIOUS_FILE=/tmp/monitors-previous
      PREVIOUS_CONNECTED=""
      [ -f "$PREVIOUS_FILE" ] && PREVIOUS_CONNECTED=$(cat "$PREVIOUS_FILE")

      is_connected() {
          echo "$CONNECTED" | awk -v output="$1" '
          /^Output:/ { in_output=0 }
          $0 ~ output { in_output=1 }
          /connected/ && in_output { found=1; exit }
          END { exit (found ? 0 : 1) }
          '
      }

      was_connected() {
          echo "$PREVIOUS_CONNECTED" | grep -q "$1"
      }

      CMD_LIST=()

      if is_connected "DP-5"; then
          was_connected "DP-5" || log "[CONNECTED] DP-5 (Primary)"
          CMD_LIST+=("output.DP-5.enable" "output.DP-5.mode.71" "output.DP-5.position.0,349" "output.DP-5.scale.1" "output.DP-5.priority.1")
      else
          was_connected "DP-5" && log "[DISCONNECTED] DP-5 (Primary)"
      fi

      if is_connected "DP-4"; then
          was_connected "DP-4" || log "[CONNECTED] DP-4 (Top)"
          CMD_LIST+=("output.DP-4.enable" "output.DP-4.mode.44" "output.DP-4.position.1920,0" "output.DP-4.scale.1" "output.DP-4.priority.2")
      else
          was_connected "DP-4" && log "[DISCONNECTED] DP-4 (Top)"
      fi

      if is_connected "DP-6"; then
          was_connected "DP-6" || log "[CONNECTED] DP-6 (Bottom)"
          CMD_LIST+=("output.DP-6.enable" "output.DP-6.mode.91" "output.DP-6.position.1920,1080" "output.DP-6.scale.1" "output.DP-6.priority.3")
      else
          was_connected "DP-6" && log "[DISCONNECTED] DP-6 (Bottom)"
      fi

      if is_connected "HDMI-A-2"; then
          was_connected "HDMI-A-2" || log "[CONNECTED] HDMI-A-2 (TV) HDR enabled"
          CMD_LIST+=("output.HDMI-A-2.enable" "output.HDMI-A-2.mode.1" "output.HDMI-A-2.position.3520,1080" "output.HDMI-A-2.scale.1.5" "output.HDMI-A-2.priority.4" "output.HDMI-A-2.hdr.enable" "output.HDMI-A-2.sdr-brightness.900")
      else
          was_connected "HDMI-A-2" && log "[DISCONNECTED] HDMI-A-2 (TV)"
      fi

      if [ ''${#CMD_LIST[@]} -gt 0 ]; then
          log "Applying configuration..."
          if kscreen-doctor "''${CMD_LIST[@]}"; then
              log "SUCCESS"
          else
              log "WARNING: Some settings failed"
          fi
      fi

      echo "$CONNECTED" > "$PREVIOUS_FILE"
      log "=== Completed ==="
    '';
  };
in
{
  # ============================================================================
  # SERVICES - Plasma 6, PipeWire, Bluetooth, Display
  # ============================================================================
  services = {
    xserver = {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
    displayManager = {
      sddm.enable = true;
      sddm.settings.General.DisplayServer = "wayland";
    };

    # KDE PLASMA 6 (Pure Wayland with XWayland fallback for legacy apps)
    desktopManager.plasma6.enable = true;

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

  # KDE portal — scoped to Plasma via xdg.portal.config.kde
  # Only active when XDG_CURRENT_DESKTOP=KDE (Plasma session)
  xdg.portal = {
    extraPortals = with pkgs; [ pkgs.kdePackages.xdg-desktop-portal-kde ];
    config.kde.default = [ "kde" ];
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
  # ELECTRON/WAYLAND COMPATIBILITY
  # ============================================================================
  environment = {
    sessionVariables = {
      # Let Electron auto-detect best backend (Wayland or XWayland)
      # Modern Electron versions work well with native Wayland
      ELECTRON_OZONE_PLATFORM_HINT = "auto";

      # GTK apps should use portal for better KDE integration
      GTK_USE_PORTAL = "1";

      # Qt6 Multimedia: Force PipeWire backend and fix library resolution
      # Fixes "qt.multimedia.symbolsresolver: Couldn't load pipewire-0.3 library"
      QT_MEDIA_BACKEND = "pipewire";
      LD_LIBRARY_PATH = lib.mkBefore [ "/run/current-system/sw/lib/pipewire-0.3" ];

      # Qt/Wayland settings (nvidia-wayland.nix may override QT_QPA_PLATFORM)
      QT_QPA_PLATFORM = lib.mkOptionDefault "wayland;xcb";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      QT_QPA_GL_VERSION = "2";

      # KWin DRM settings for multi-GPU systems
      # NOTE: Do NOT set KWIN_DRM_DEVICE (singular) — it overrides KWIN_DRM_DEVICES
      # and card0 doesn't exist on this system (cards start at card1).
      # plasma6.nix handles KWIN_DRM_DEVICES correctly.
    };

    systemPackages = with pkgs.kdePackages; [
      # Core Plasma Desktop
      plasma-workspace
      plasma-desktop
      plasma-systemmonitor

      # Full Plasma Applications Suite
      discover
      dolphin
      dolphin-plugins
      konsole
      kate
      ark
      gwenview
      okular
      kde-gtk-config
      plasma-pa
      plasma-nm
      bluedevil
      spectacle
      kdeplasma-addons
      filelight
      kde-cli-tools
      kde-inotify-survey

      # Monitor setup scripts
      monitorSetupScript
      pkgs.libnotify

      # DDC/CI brightness control for external monitors
      pkgs.ddcutil
    ];

    etc = {
      "xdg/kscreenlockerrc".text = ''
        [Daemon]
        Autolock=false
        Enabled=false
        Timeout=0
      '';

      # PowerDevil - Disable display power management, enable brightness control for all monitors
      # Uses ddcutil for DDC/CI brightness control on external monitors
      "xdg/powerdevilrc".text = ''
        [AC][Display]
        DimDisplayIdleTimeoutSec=-1
        DimDisplayWhenIdle=false
        DimScreen=false
        TurnOffDisplayIdleTimeoutSec=600
        TurnOffDisplayWhenIdle=false

        [Battery][Display]
        DimDisplayIdleTimeoutSec=0
        DimScreen=false
        TurnOffDisplayIdleTimeoutSec=300
        TurnOffDisplayWhenIdle=false

        [DPMSControl]
        enable=false

        [Daemon]
        Enabled=true
      '';

      # Power Management Profile - Manual brightness control for all monitors
      "xdg/powermanagementprofilesrc".text = ''
        [AC]
        # Disable auto-dimming based on activity (prevents HDMI TV from dimming when idle)
        [AC][Display]
        DimScreen=false
        # Turn off screen after long inactivity (not auto-dim)
        DisplayTurnOff=600

        [Battery][Display]
        DimScreen=false
        DisplayTurnOff=300

        # Brightness Control - Enable manual slider, disable automatic adjustments
        [Battery][BrightnessControl]
        brightnessEnable=true
        # Use profile-specific brightness means auto-adjust based on activity - DISABLE THIS
        useProfileSpecificDisplayBrightness=false

        [AC][BrightnessControl]
        brightnessEnable=true
        useProfileSpecificDisplayBrightness=false

        # Global power management settings
        [General]
        # Disable automatic brightness control based on ambient light
        useAutoBrightness=false
        # Don't suspend automatically (user choice)
        autosuspendEnabled=false

        # Display settings
        [Display][BrightnessControl]
        brightnessEnable=true
        useProfileSpecificDisplayBrightness=false

        # Profile independent settings
        [Battery][Activities]
        [AC][Activities]
      '';

      "xdg/kwinrc".text = ''
        [Compositing]
        AllowTearing=false
        GLVSync=true
        AnimationSpeed=3
      '';

      # Window rules for specific applications (Genshin Impact only - Spotify excluded)
      "xdg/kwinrulesrc".text = ''
        [General]
        count=1

        # Genshin Impact - Always open on TV (HDMI-A-2)
        [1]
        Description=Genshin Impact - Always on TV (HDMI-A-2)
        wmclass=.*GenshinImpact.*
        wmclassmatch=2
        screen=3
        screenrule=3
        fullscreen=true
        fullscreenrule=3
        types=1
      '';

      # Disable KScreen KDED module (we handle monitors ourselves)
      "xdg/kdedrc".text = ''
        [Module-kscreen]
        Enabled=false
      '';

      # autostart entries defined in plasma6.nix (plasma-monitor-setup.desktop,
      # tv-monitor-daemon.desktop) — removed duplicates to avoid conflicts
    };
  };

  # ============================================================================
  # SYSTEMD SERVICES
  # ============================================================================
  # All systemd user services (gpu-ready, boot-monitor-setup, plasma-monitor-setup,
  # tv-monitor-daemon) defined in plasma6.nix — removed duplicates here
  systemd.user.services."kscreen_backend_launcher".enable = false;
}
