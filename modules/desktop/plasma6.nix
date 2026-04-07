# KDE Plasma 6 Desktop Environment
{
  lib,
  pkgs,
  config,
  ...
}:
let
  monitorSetupScript = pkgs.writeShellApplication {
    name = "plasma-monitor-setup";
    runtimeInputs = with pkgs; [
      kdePackages.kscreen
      libnotify
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/plasma-monitor-setup"
      mkdir -p "$STATE_DIR"
      LOGFILE="$STATE_DIR/plasma-monitor-setup.log"
      NOTIFY_LOG="$STATE_DIR/monitor-events.log"
      log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$NOTIFY_LOG"
          notify-send "Monitor Setup" "$1" -i video-display 2>/dev/null || true
      }
      log "=== Monitor setup started ==="
      CONNECTED=$(kscreen-doctor -o 2>/dev/null || true)
      [ -z "$CONNECTED" ] && { log "No outputs detected"; exit 0; }
      PREVIOUS_FILE="$STATE_DIR/monitors-previous"
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
  bootMonitorScript = pkgs.writeShellScript "boot-monitor-setup" ''
    sleep 2
    ${monitorSetupScript}/bin/plasma-monitor-setup
  '';
  # TV Monitor Daemon for automatic TV power management
  tvMonitorDaemon = pkgs.writeShellApplication {
    name = "tv-monitor-daemon";
    runtimeInputs = with pkgs; [
      kdePackages.kscreen
      libnotify
      wireplumber
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/tv-monitor-daemon"
      mkdir -p "$STATE_DIR"
      LOGFILE="$STATE_DIR/tv-monitor-daemon.log"
      TV_STATE_FILE="$STATE_DIR/tv-state"
      HDMI_OUTPUT="HDMI-A-2"
      log() {
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
      }
      notify() {
          notify-send "TV Monitor" "$1" -i video-display 2>/dev/null || true
      }
      # Get current TV connection state
      is_tv_connected() {
          kscreen-doctor -o 2>/dev/null | grep -q "$HDMI_OUTPUT.*connected"
      }
      # Get current TV enabled state
      is_tv_enabled() {
          kscreen-doctor -o 2>/dev/null | grep -A 3 "$HDMI_OUTPUT" | grep -q "enabled"
      }
      # Check if TV is actually ON (not just connected)
      # A TV can be connected but in standby/power-save mode
      is_tv_powered_on() {
          # Check if the display is actually accepting signals
          # We'll detect this by seeing if it's in the connected outputs
          is_tv_connected && is_tv_enabled
      }
      # Disable TV output and switch audio away
      disable_tv() {
          log "TV DISABLING: Disabling $HDMI_OUTPUT and switching audio"
          notify "TV turned off - Disabling display and audio"
          # Disable the TV output (atomic, no other displays affected)
          kscreen-doctor "output.$HDMI_OUTPUT.disable" 2>/dev/null || true
          # Move default audio away from HDMI if it was default
          if wpctl status 2>/dev/null | grep -q "Default Sink:.*hdmi"; then
              # Find first non-HDMI audio sink
              local fallback_sink
              fallback_sink=$(wpctl status short 2>/dev/null | grep -v "hdmi" | grep -v "DualSense" | head -1 | awk '{print $1}')
              if [ -n "$fallback_sink" ]; then
                  log "Switching audio from HDMI to: $fallback_sink"
                  wpctl set-default "$fallback_sink" 2>/dev/null || true
              fi
          fi
          echo "disabled" > "$TV_STATE_FILE"
          log "TV disabled successfully"
      }
      # Enable and configure TV output
      enable_tv() {
          log "TV ENABLING: Enabling and configuring $HDMI_OUTPUT"
          notify "TV turned on - Enabling display with HDR"
          # Enable and configure TV with all settings atomically
          kscreen-doctor \
              "output.$HDMI_OUTPUT.enable" \
              "output.$HDMI_OUTPUT.mode.1" \
              "output.$HDMI_OUTPUT.position.3520,1080" \
              "output.$HDMI_OUTPUT.scale.1.5" \
              "output.$HDMI_OUTPUT.priority.4" \
              "output.$HDMI_OUTPUT.hdr.enable" \
              "output.$HDMI_OUTPUT.sdr-brightness.900" \
              2>/dev/null || log "WARNING: TV configuration failed"
          # Note: We DON'T force audio to HDMI - let user choose
          # But we make sure audio isn't stuck on a disconnected sink
          echo "enabled" > "$TV_STATE_FILE"
          log "TV enabled successfully"
      }
      # Main monitoring loop
      log "=== TV Monitor Daemon starting ==="
      # Initialize state
      PREVIOUS_STATE="unknown"
      [ -f "$TV_STATE_FILE" ] && PREVIOUS_STATE=$(cat "$TV_STATE_FILE")
      log "Starting TV state monitoring loop..."
      log "Current TV state: $PREVIOUS_STATE"
      # Monitor interval (seconds) - check every 5 seconds
      CHECK_INTERVAL=5
      while true; do
          # Check if TV is connected AND enabled
          if is_tv_powered_on; then
              CURRENT_STATE="on"
          else
              CURRENT_STATE="off"
          fi
          # State machine
          if [ "$PREVIOUS_STATE" = "on" ] && [ "$CURRENT_STATE" = "off" ]; then
              # TV turned OFF
              disable_tv
              PREVIOUS_STATE="off"
          elif [ "$PREVIOUS_STATE" = "off" ] && [ "$CURRENT_STATE" = "on" ]; then
              # TV turned ON
              enable_tv
              PREVIOUS_STATE="on"
          elif [ "$PREVIOUS_STATE" = "unknown" ]; then
              # First run - set correct state without logging
              if [ "$CURRENT_STATE" = "on" ]; then
                  log "TV detected as ON at startup"
              else
                  log "TV detected as OFF at startup"
              fi
              PREVIOUS_STATE="$CURRENT_STATE"
          fi
          sleep "$CHECK_INTERVAL"
      done
    '';
  };
  # KDE cache management scripts removed - they were causing crashes
  # KDE will auto-rebuild its cache as needed
  # Cache clearing script for post-rebuild cleanup
  clearKdeCacheScript = pkgs.writeShellScript "clear-kde-cache" ''
    # Clear KDE/QML cache after nixos-rebuild (prevents desktop file errors)
    # This fixes Spectacle "Unable to make service executable" errors
    find ''${XDG_CACHE_HOME:-$HOME/.cache} -name "qmlcache" -type d -exec rm -rf {} + 2>/dev/null || true
    rm -rf ~/.cache/kwin* ~/.cache/plasma* ~/.cache/ksycoca* 2>/dev/null || true
  '';
in
{
  # Add KDE xdg-desktop-portal when Plasma is enabled
  xdg.portal.extraPortals = with pkgs; [ pkgs.kdePackages.xdg-desktop-portal-kde ];
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
      sddm.settings.Wayland.SessionDir = toString (pkgs.runCommandLocal "wayland-sessions-filtered" { } ''
          mkdir -p $out
          for f in ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions/*.desktop; do
            bn=$(basename "$f")
            if [ "$bn" != "hyprland.desktop" ]; then
              ln -s "$f" "$out/$bn"
            fi
          done
        '');
      # autoLogin is configured in common-host-defaults.nix to avoid duplication
      autoLogin.enable = lib.mkDefault true;
      autoLogin.user = lib.mkDefault "j_kro";
    };
  };
  environment = {
    sessionVariables = {
      QT_QPA_PLATFORM = "wayland;xcb";
      # NOTE: QT_WAYLAND_DISABLE_WINDOWDECORATION removed - it breaks Discover (plasma-discover)
      # Spotify's close button issue is handled by KWin window rule (see kwinrulesrc below)
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      # NOTE: QT_USE_RHI_GLES2 removed - can cause rendering issues with some Qt apps
      QT_QPA_GL_VERSION = "2";
    };
    systemPackages = with pkgs.kdePackages; [
      # Core Plasma Desktop
      plasma-workspace
      plasma-desktop
      plasma-systemmonitor
      # Full Plasma Applications Suite
      # Discover - Software Center (what user was missing!)
      discover
      # File manager
      dolphin
      dolphin-plugins
      # Terminal
      konsole
      # Text editor
      kate
      # Archive manager
      ark
      # Image viewer
      gwenview
      # PDF viewer
      okular
      # System settings additional modules
      kde-gtk-config
      # Audio volume control
      plasma-pa
      # Network manager applet
      plasma-nm
      # Bluetooth
      bluedevil
      # Spectacle - Screenshots
      spectacle
      # Extra desktop widgets
      kdeplasma-addons
      # Disk usage analyzer
      filelight
      # Utilities
      kde-cli-tools
      kde-inotify-survey
      # Monitor setup script
      monitorSetupScript
      pkgs.libnotify
      # DDC/CI brightness control for external monitors
      pkgs.ddcutil
    ];
    etc = {
      "xdg/kscreenlockerrc".text = ''
        [General]
        [Screen]
        AutoscreenDisabled=true
        [Daemon]
        AutoConfig=false
      '';
      "xdg/kwinrc".text = ''
        [Compositing]
        AllowTearing=false
        GLVSync=true
        AnimationSpeed=3
      '';
      # Powerdevil configuration - Manual brightness control, NO automatic adjustments
      # This restores the brightness slider to the system tray while preventing HDMI TV issues
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
      # Powerdevil runtime configuration - Enable brightness control for ALL displays
      # DP-6 (Acer X203H) DOES support DDC/CI (i2c-10) - intermittent detection is a PowerDevil bug
      "xdg/powerdevilrc".text = ''
        [AC][Display]
        DimDisplayIdleTimeoutSec=-1
        DimDisplayWhenIdle=false
        DimScreen=false
        TurnOffDisplayIdleTimeoutSec=600
        TurnOffDisplayWhenIdle=false
        [AC][SuspendAndShutdown]
        AutoSuspendAction=0
        [ActivityFinder]
        DontDetectDontDetect=true
        [Battery][Display]
        DimDisplayIdleTimeoutSec=0
        DimScreen=false
        TurnOffDisplayIdleTimeoutSec=300
        TurnOffDisplayWhenIdle=false
        [BrightnessControl]
        # CRITICAL: UseDDCUtil=false shows ALL displays (including non-DDC/CI)
        # UseDDCUtil=true only shows DDC/CI-capable displays (hides Samsung TV)
        UseDDCUtil=false
        # Explicit brightness control for each display - ALL ENABLED
        # DP-5 (Primary 1920x1080 ZOWIE) - DDC/CI supported ✓
        [DP-5][BrightnessControl]
        brightnessEnable=true
        brightnessValue=100
        # DP-4 (Top 1920x1080 ASUS) - DDC/CI supported ✓
        [DP-4][BrightnessControl]
        brightnessEnable=true
        brightnessValue=100
        # DP-6 (Bottom 1600x900 Acer X203H) - DDC/CI supported ✓ (i2c-10)
        [DP-6][BrightnessControl]
        brightnessEnable=true
        brightnessValue=100
        # HDMI-A-2 (TV 4K HDR Samsung) - NO DDC/CI but MUST show in slider
        [HDMI-A-2][BrightnessControl]
        brightnessEnable=true
        brightnessValue=100
        [DPMSControl]
        enable=false
        [Daemon]
        Enabled=true
        [General]
        useAutoBrightness=false
      '';
      # Window rules for specific applications
      "xdg/kwinrulesrc".text = ''
        [General]
        count=2
        # Spotify - Force server-side decorations to fix broken close button on Wayland
        # Spotify's Electron CSD don't work properly on Wayland, causing SIGTRAP in libcef.so
        [1]
        Description=Spotify - Force SSD decorations for working close button
        wmclass=spotify
        wmclasscomplete=true
        wmclassmatch=1
        title=
        titlematch=0
        types=1
        nonswitch=true
        acceptfocus=true
        autotype=true
        closeable=true
        fullscreen=false
        fullscreenrule=0
        maximize=true
        maximizerule=0
        minimize=true
        minimizerule=0
        noborder=false
        noborderrule=3
        skippager=false
        skipswitcher=false
        skiptaskbar=false
        abovenoborder=true
        # Genshin Impact - Always open on TV (HDMI-A-2)
        [2]
        Description=Genshin Impact - Always on TV (HDMI-A-2)
        wmclass=.*GenshinImpact.*
        wmclassmatch=2
        screen=1
        screenrule=3
        fullscreen=true
        fullscreenrule=3
        types=1
      '';
      # Disable KScreen KDED module
      "xdg/kdedrc".text = ''
        [Module-kscreen]
        Enabled=false
      '';
      # NOTE: KDE cache management removed - let KDE handle its own cache
      # Auto-rebuild happens naturally when needed
      "xdg/autostart/plasma-monitor-setup.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Monitor Setup
        Exec=${monitorSetupScript}/bin/plasma-monitor-setup
        X-KDE-autostart-phase=2
        NoDisplay=true
      '';
      "xdg/autostart/tv-monitor-daemon.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=TV Monitor Daemon
        Exec=${tvMonitorDaemon}/bin/tv-monitor-daemon
        X-KDE-autostart-phase=3
        NoDisplay=true
      '';
      # Ensure PowerDevil has correct config with all 4 displays at startup
      # Previous version used 'touch' which created empty file and broke detection
      "xdg/autostart/ensure-powerdevil-displays.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Ensure PowerDevil Display Detection
        Exec=${pkgs.writeShellScript "ensure-powerdevil-displays" ''
          # Wait for Plasma to fully start
          sleep 5

          CONFIG="$HOME/.config/powerdevilrc"
          SYSTEM_CONFIG="/etc/xdg/powerdevilrc"

          # If user config is missing or empty, copy from system config
          if [ ! -s "$CONFIG" ]; then
            cp "$SYSTEM_CONFIG" "$CONFIG" 2>/dev/null || true
          fi

          # If config is missing DP-6 (Acer), it's incomplete - restore system config
          if ! grep -q "\[DP-6\]\[BrightnessControl\]" "$CONFIG" 2>/dev/null; then
            cp "$SYSTEM_CONFIG" "$CONFIG" 2>/dev/null || true
          fi

          # Trigger brightness control refresh via DBus
          ${pkgs.dbus}/bin/dbus-send --session --dest=org.kde.Solid.PowerDevil \
            --type=method_call /org/kde/Solid/PowerDevil \
            org.kde.Solid.PowerDevil.refreshStatus 2>/dev/null || true
        ''}
        X-KDE-autostart-phase=3
        NoDisplay=true
      '';
    };
  };
  systemd = {
    # GPU Readiness Service - Ensures GPU devices are ready before display manager starts
    # This fixes a race condition where SDDM autologin fails because /dev/dri/card* isn't ready
    # Supports both NVIDIA (CUDA) and AMD (ROCm) GPUs
    services.gpu-ready = {
      description = "Wait for GPU devices to be ready";
      after = [ "systemd-modules-load.service" ];
      wantedBy = [ "display-manager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "gpu-ready" ''
          # Wait for GPU DRM devices to be ready (NVIDIA/CUDA or AMD/ROCm)
          # NVIDIA: /proc/driver/nvidia, /dev/nvidiactl
          # AMD: /sys/class/drm/card*/device/vendor (0x1002 = AMD)
          log() {
            echo "[gpu-ready] $1" >&2
          }
          # Check if any DRM device exists and is accessible
          check_drm_devices() {
            for dev in /dev/dri/card*; do
              if [ -e "$dev" ] && [ -r "$dev" ]; then
                return 0
              fi
            done
            return 1
          }
          # Check for NVIDIA GPUs (CUDA)
          has_nvidia() {
            [ -d /proc/driver/nvidia ] && [ -e /dev/nvidiactl ]
          }
          # Check for AMD GPUs (ROCm)
          has_amd() {
            [ -d /sys/class/drm ] && grep -q "0x1002" /sys/class/drm/card*/device/vendor 2>/dev/null
          }
          # Wait for NVIDIA driver to fully load
          wait_nvidia() {
            local max_attempts=30
            for i in $(seq 1 $max_attempts); do
              if [ -e /dev/nvidiactl ] && [ -r /dev/nvidiactl ]; then
                return 0
              fi
              sleep 0.5
            done
            return 1
          }
          DETECTED_GPUS=""
          has_nvidia && {
            DETECTED_GPUS="$DETECTED_GPUS NVIDIA(CUDA)"
            log "Waiting for NVIDIA driver to fully initialize..."
            wait_nvidia || log "WARNING: NVIDIA driver may not be fully initialized"
          }
          has_amd && DETECTED_GPUS="$DETECTED_GPUS AMD(ROCm)"
          if [ -n "$DETECTED_GPUS" ]; then
            log "Detected GPUs:$DETECTED_GPUS"
          else
            log "No GPUs detected, waiting for DRM devices..."
          fi
          # Wait up to 15 seconds for DRM devices to be accessible
          for i in $(seq 1 75); do
            if check_drm_devices; then
              log "DRM devices ready at /dev/dri/"
              ls -la /dev/dri/card* 2>/dev/null || true
              exit 0
            fi
            sleep 0.2
          done
          # Timeout - log warning but proceed (display manager has restart logic)
          log "WARNING: Timeout waiting for DRM devices, proceeding anyway"
          exit 0
        '';
      };
    };
    services.clear-kde-cache-after-rebuild = {
      description = "Clear KDE/QML cache after nixos-rebuild";
      wantedBy = [ "multi-user.target" ];
      after = [ "nixos-rebuild.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = clearKdeCacheScript;
        RemainAfterExit = true;
      };
    };
    # boot-monitor-setup DISABLED - Caused autologin failure!
    # The root-level monitor setup conflicts with KWin's atomic modeset at boot.
    # Monitor configuration is now handled by user-space plasma-monitor-setup after login.
    # services.boot-monitor-setup = {
    #   description = "Configure monitors at boot";
    #   wantedBy = ["display-manager.service"];
    #   before = [
    #     "display-manager.service"
    #     "sddm.service"
    #   ];
    #   after = [
    #     "local-fs.target"
    #     "tmp.mount"
    #   ];
    #   serviceConfig = {
    #     Type = "oneshot";
    #     ExecStart = bootMonitorScript;
    #     RemainAfterExit = true;
    #     TimeoutStartSec = 10;
    #     User = "root";
    #     Group = "root";
    #     StandardOutput = "journal";
    #     StandardError = "journal";
    #   };
    # };
    user.services = {
      plasma-monitor-setup = {
        description = "Apply monitor configuration";
        wantedBy = [ "graphical-session.target" ];
        after = [
          "plasma-plasmashell.service"
          "graphical-session.target"
        ];
        # Only run when Plasma is the active VT (tty1).
        # When the user switches to niri (tty2) or hyprland (tty3),
        # KWin loses DRM master and kscreen-doctor calls fail with
        # "Atomic modeset test failed: Permission denied".
        serviceConfig.ExecCondition = pkgs.writeShellScript "plasma-vt-check" ''
          ACTIVE_TTY=$(cat /sys/class/tty/tty0/active 2>/dev/null || echo tty0)
          [ "$ACTIVE_TTY" = "tty1" ]
        '';
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${monitorSetupScript}/bin/plasma-monitor-setup";
          Restart = "on-failure";
          RestartSec = 2;
        };
      };
      # Disable KScreen backend launcher
      "kscreen_backend_launcher".enable = false;
      # TV Monitor Daemon - Auto manage TV power state
      # Only active when Plasma is on tty1 — prevents kscreen-doctor spam
      # that causes "Atomic modeset test failed: Permission denied" when
      # KWin doesn't hold DRM master (user switched to another VT).
      tv-monitor-daemon = {
        description = "Monitor TV power state and auto-disable/enable";
        wantedBy = [ "graphical-session.target" ];
        after = [
          "plasma-plasmashell.service"
          "graphical-session.target"
        ];
        serviceConfig.ExecCondition = pkgs.writeShellScript "tv-monitor-vt-check" ''
          ACTIVE_TTY=$(cat /sys/class/tty/tty0/active 2>/dev/null || echo tty0)
          [ "$ACTIVE_TTY" = "tty1" ]
        '';
        serviceConfig = {
          Type = "simple";
          ExecStart = "${tvMonitorDaemon}/bin/tv-monitor-daemon";
          Restart = "always";
          RestartSec = 5;
        };
      };
    };
  };
}
