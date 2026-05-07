{
  lib,
  pkgs,
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
      is_tv_connected() {
          kscreen-doctor -o 2>/dev/null | grep -q "$HDMI_OUTPUT.*connected"
      }
      is_tv_enabled() {
          kscreen-doctor -o 2>/dev/null | grep -A 3 "$HDMI_OUTPUT" | grep -q "enabled"
      }
      is_tv_powered_on() {
          is_tv_connected && is_tv_enabled
      }
      disable_tv() {
          log "TV DISABLING: Disabling $HDMI_OUTPUT and switching audio"
          notify "TV turned off - Disabling display and audio"
          kscreen-doctor "output.$HDMI_OUTPUT.disable" 2>/dev/null || true
          if wpctl status 2>/dev/null | grep -q "Default Sink:.*hdmi"; then
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
      enable_tv() {
          log "TV ENABLING: Enabling and configuring $HDMI_OUTPUT"
          notify "TV turned on - Enabling display with HDR"
          kscreen-doctor \
              "output.$HDMI_OUTPUT.enable" \
              "output.$HDMI_OUTPUT.mode.1" \
              "output.$HDMI_OUTPUT.position.3520,1080" \
              "output.$HDMI_OUTPUT.scale.1.5" \
              "output.$HDMI_OUTPUT.priority.4" \
              "output.$HDMI_OUTPUT.hdr.enable" \
              "output.$HDMI_OUTPUT.sdr-brightness.900" \
              2>/dev/null || log "WARNING: TV configuration failed"
          echo "enabled" > "$TV_STATE_FILE"
          log "TV enabled successfully"
      }
      log "=== TV Monitor Daemon starting ==="
      PREVIOUS_STATE="unknown"
      [ -f "$TV_STATE_FILE" ] && PREVIOUS_STATE=$(cat "$TV_STATE_FILE")
      log "Starting TV state monitoring loop..."
      log "Current TV state: $PREVIOUS_STATE"
      CHECK_INTERVAL=5
      while true; do
          if is_tv_powered_on; then
              CURRENT_STATE="on"
          else
              CURRENT_STATE="off"
          fi
          if [ "$PREVIOUS_STATE" = "on" ] && [ "$CURRENT_STATE" = "off" ]; then
              disable_tv
              PREVIOUS_STATE="off"
          elif [ "$PREVIOUS_STATE" = "off" ] && [ "$CURRENT_STATE" = "on" ]; then
              enable_tv
              PREVIOUS_STATE="on"
          elif [ "$PREVIOUS_STATE" = "unknown" ]; then
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
  clearKdeCacheScript = pkgs.writeShellScript "clear-kde-cache" ''
    find ''${XDG_CACHE_HOME:-$HOME/.cache} -name "qmlcache" -type d -exec rm -rf {} + 2>/dev/null || true
    rm -rf ~/.cache/kwin* ~/.cache/plasma* ~/.cache/ksycoca* 2>/dev/null || true
  '';
in {
  options.desktop.plasma6.enable = lib.mkEnableOption "KDE Plasma 6 desktop environment";

  config = lib.mkIf config.desktop.plasma6.enable (lib.mkMerge [
    {
      xdg.portal.extraPortals = with pkgs; [pkgs.kdePackages.xdg-desktop-portal-kde];
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
          sddm.settings.Wayland.SessionDir = toString (pkgs.runCommandLocal "wayland-sessions-filtered" {} ''
            mkdir -p $out
            for f in ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions/*.desktop; do
              bn=$(basename "$f")
              if [ "$bn" != "hyprland.desktop" ]; then
                ln -s "$f" "$out/$bn"
              fi
            done
          '');
          autoLogin.enable = lib.mkDefault true;
          autoLogin.user = lib.mkDefault "j_kro";
        };
      };
      environment = {
        sessionVariables = {
          QT_QPA_PLATFORM = "wayland;xcb";
          QT_AUTO_SCREEN_SCALE_FACTOR = "1";
          QT_QPA_GL_VERSION = "2";
        };
        systemPackages = with pkgs.kdePackages; [
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
            UseDDCUtil=false
            [DP-5][BrightnessControl]
            brightnessEnable=true
            brightnessValue=100
            [DP-4][BrightnessControl]
            brightnessEnable=true
            brightnessValue=100
            [DP-6][BrightnessControl]
            brightnessEnable=true
            brightnessValue=100
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
          "xdg/kwinrulesrc".text = ''
            [General]
            count=2
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
          "xdg/kdedrc".text = ''
            [Module-kscreen]
            Enabled=false
          '';
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
          "xdg/autostart/ensure-powerdevil-displays.desktop".text = ''
            [Desktop Entry]
            Type=Application
            Name=Ensure PowerDevil Display Detection
            Exec=${pkgs.writeShellScript "ensure-powerdevil-displays" ''
              sleep 5

              CONFIG="$HOME/.config/powerdevilrc"
              SYSTEM_CONFIG="/etc/xdg/powerdevilrc"

              if [ ! -s "$CONFIG" ]; then
                cp "$SYSTEM_CONFIG" "$CONFIG" 2>/dev/null || true
              fi

              if ! grep -q "\[DP-6\]\[BrightnessControl\]" "$CONFIG" 2>/dev/null; then
                cp "$SYSTEM_CONFIG" "$CONFIG" 2>/dev/null || true
              fi

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
        services.gpu-ready = {
          description = "Wait for GPU devices to be ready";
          after = ["systemd-modules-load.service"];
          wantedBy = ["display-manager.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "gpu-ready" ''
              log() {
                echo "[gpu-ready] $1" >&2
              }
              check_drm_devices() {
                for dev in /dev/dri/card*; do
                  if [ -e "$dev" ] && [ -r "$dev" ]; then
                    return 0
                  fi
                done
                return 1
              }
              has_nvidia() {
                [ -d /proc/driver/nvidia ] && [ -e /dev/nvidiactl ]
              }
              has_amd() {
                [ -d /sys/class/drm ] && grep -q "0x1002" /sys/class/drm/card*/device/vendor 2>/dev/null
              }
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
              for i in $(seq 1 75); do
                if check_drm_devices; then
                  log "DRM devices ready at /dev/dri/"
                  ls -la /dev/dri/card* 2>/dev/null || true
                  exit 0
                fi
                sleep 0.2
              done
              log "WARNING: Timeout waiting for DRM devices, proceeding anyway"
              exit 0
            '';
          };
        };
        services.clear-kde-cache-after-rebuild = {
          description = "Clear KDE/QML cache after nixos-rebuild";
          wantedBy = ["multi-user.target"];
          after = ["nixos-rebuild.service"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = clearKdeCacheScript;
            RemainAfterExit = true;
          };
        };
        user.services = {
          plasma-monitor-setup = {
            description = "Apply monitor configuration";
            wantedBy = ["graphical-session.target"];
            after = [
              "plasma-plasmashell.service"
              "graphical-session.target"
            ];
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
          "kscreen_backend_launcher".enable = false;
          tv-monitor-daemon = {
            description = "Monitor TV power state and auto-disable/enable";
            wantedBy = ["graphical-session.target"];
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
  ]);
}
