{
  pkgs,
  lib,
  config,
  ...
}: let
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
in {
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

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;

      extraConfig = {
        pipewire."99-lowlatency" = {
          "context.properties" = {
            "default.clock.min-quantum" = 1024;
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
        pipewire-pulse."99-lowlatency"."pulse.min.quantum" = "1024/48000";
        client."99-lowlatency"."stream.properties"."node.latency" = "1024/48000";
      };
    };

    pulseaudio.enable = false;

    blueman.enable = true;

    upower.enable = true;
  };

  # Fix: blueman-applet has duplicate ExecStart from systemd.packages install + NixOS auto-override
  # Clear ExecStart explicitly to replace (not add to) the packaged unit.
  systemd.user.services.blueman-applet.serviceConfig.ExecStart = lib.mkForce ["" "${pkgs.blueman}/bin/blueman-applet"];

  xdg.portal = lib.mkIf config.services.desktopManager.plasma6.enable {
    extraPortals = with pkgs; [pkgs.kdePackages.xdg-desktop-portal-kde];
    config.kde.default = ["kde"];
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  security = {
    rtkit.enable = true;

    pam.loginLimits = [
      {
        domain = "@audio";
        item = "rtprio";
        type = "-";
        value = "95";
      }
      {
        domain = "@audio";
        item = "nice";
        type = "-";
        value = "-11";
      }
      {
        domain = "@users";
        item = "memlock";
        type = "-";
        value = "unlimited";
      }
    ];

    pam.services.sddm.enableKwallet = lib.mkIf config.services.desktopManager.plasma6.enable true;
  };

  environment = {
    sessionVariables = {
      ELECTRON_OZONE_PLATFORM_HINT = "auto";

      GTK_USE_PORTAL = "1";

      QT_MEDIA_BACKEND = "pipewire";
      # LD_LIBRARY_PATH = lib.mkBefore "/run/current-system/sw/lib/pipewire-0.3";

      QT_QPA_PLATFORM = lib.mkOptionDefault "wayland;xcb";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      QT_QPA_GL_VERSION = "2";
    };

    systemPackages = lib.mkIf config.services.desktopManager.plasma6.enable (
      with pkgs.kdePackages; [
        plasma-workspace
        plasma-desktop
        plasma-systemmonitor

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

        monitorSetupScript
        pkgs.libnotify

        pkgs.ddcutil
      ]
    );

    etc = lib.mkIf config.services.desktopManager.plasma6.enable {
      "xdg/kscreenlockerrc".text = ''
        [Daemon]
        Autolock=false
        Enabled=false
        Timeout=0
      '';

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

      "xdg/powermanagementprofilesrc".text = ''
        [AC]
        [AC][Display]
        DimScreen=false
        DisplayTurnOff=600

        [Battery][Display]
        DimScreen=false
        DisplayTurnOff=300

        [Battery][BrightnessControl]
        brightnessEnable=true
        useProfileSpecificDisplayBrightness=false

        [AC][BrightnessControl]
        brightnessEnable=true
        useProfileSpecificDisplayBrightness=false

        [General]
        useAutoBrightness=false
        autosuspendEnabled=false

        [Display][BrightnessControl]
        brightnessEnable=true
        useProfileSpecificDisplayBrightness=false

        [Battery][Activities]
        [AC][Activities]
      '';

      "xdg/kwinrc".text = ''
        [Compositing]
        AllowTearing=false
        GLVSync=true
        AnimationSpeed=3
      '';

      "xdg/kwinrulesrc".text = ''
        [General]
        count=1

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

      "xdg/kdedrc".text = ''
        [Module-kscreen]
        Enabled=false
      '';
    };
  };

  systemd.user.services."kscreen_backend_launcher".enable =
    lib.mkIf (!config.services.desktopManager.plasma6.enable) false;
}
