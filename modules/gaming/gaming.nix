# Gaming Module - Steam, GameMode, Gamescope, MangoHud
# VR (WiVRn) is gated by services.gaming.vr.enable option
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.gaming;
  vrCfg = cfg.vr;
in {
  options.services.gaming = {
    enable = mkEnableOption "Gaming support (Steam, GameMode, Gamescope)";

    disableCabcTriggers = mkEnableOption "Disable CABC triggers for HDMI TVs";

    vr = {
      enable = mkEnableOption "VR support (WiVRn, SteamVR, OpenXR)";
      encoder = mkOption {
        type = types.enum ["nvenc" "x264" "av1"];
        default = "nvenc";
        description = "Video encoder for WiVRn streaming";
      };
      refreshRate = mkOption {
        type = types.int;
        default = 90;
        description = "Target refresh rate for VR headset";
      };
      resolution = mkOption {
        type = types.str;
        default = "2160x2160";
        description = "Per-eye resolution for VR streaming";
      };
    };
  };

  config = mkMerge [
    # Base gaming configuration (always when gaming.enable = true)
    (mkIf cfg.enable {
      # ============================================================================
      # PROGRAMS - GameMode, Steam, Gamescope, nix-ld
      # ============================================================================
      programs = {
        # GameMode - CPU/GPU Optimizations
        gamemode = {
          enable = true;
          settings = {
            general = {
              desiredgov = "performance";
              use_systemd = true;
              softrealtime = "auto";
              renice = 15;
              ioprio = 0;
            };
            gpu = {
              apply_gpu_optimisations = "accept-responsibility";
              nv_powermizer_mode = 1;
              # Moderate overclock values - balanced stability/performance
              # Conservative: 50MHz core, 200MHz memory (safer starting point)
              # Current: 100MHz core, 400MHz memory (balanced)
              # Aggressive: 150MHz core, 500MHz memory (may cause instability)
              nv_core_clock_mhz_offset = 100;
              nv_mem_clock_mhz_offset = 400;
            };
            custom = {
              start = "${pkgs.writeShellScript "gamemode-start" ''
                ${pkgs.libnotify}/bin/notify-send 'GameMode activated' 'Performance optimizations enabled'

                # Pause flexible XMRig instance during gaming
                if systemctl is-active --quiet xmrig-flexible 2>/dev/null; then
                  echo "[$(date '+%Y-%m-%d %H:%M:%S')] GameMode: Pausing xmrig-flexible" >> /var/log/gamemode-mining.log
                  systemctl stop xmrig-flexible
                  ${pkgs.libnotify}/bin/notify-send 'Mining paused' 'Flexible XMRig instance paused during gaming'
                fi
              ''}";
              end = "${pkgs.writeShellScript "gamemode-end" ''
                ${pkgs.libnotify}/bin/notify-send 'GameMode deactivated' 'Normal performance restored'

                # Resume flexible XMRig instance after gaming
                if ! systemctl is-active --quiet xmrig-flexible 2>/dev/null; then
                  echo "[$(date '+%Y-%m-%d %H:%M:%S')] GameMode: Resuming xmrig-flexible" >> /var/log/gamemode-mining.log
                  systemctl start xmrig-flexible
                  ${pkgs.libnotify}/bin/notify-send 'Mining resumed' 'Flexible XMRig instance resumed'
                fi
              ''}";
            };
          };
        };

        # Steam - Game launcher and Proton manager
        steam = {
          enable = true;
          fontPackages = with pkgs; [
            noto-fonts
            liberation_ttf
            dejavu_fonts
          ];
          extraCompatPackages = [
            # Temporarily disabled nixpkgs-xr packages due to deprecated options
            # optionals (inputs != null && inputs ? nixpkgs-xr) [
            #   inputs.nixpkgs-xr.packages."x86_64-linux".proton-ge-rtsp-bin
            # ];
          ];
          package = pkgs.steam.override {
            extraLibraries = pkgs:
              with pkgs; [
                freetype
                fontconfig
                libpng
                libjpeg
                libtiff
                vulkan-loader
                vulkan-tools
                libxcursor
                libxi
                libxinerama
                libxscrnsaver
                libpulseaudio
                libvorbis
                stdenv.cc.cc.lib
                libkrb5
                keyutils
                libcap
                SDL2
              ];
            extraProfile = ''
              # LVRA recommendation for VRChat timezone display
              unset TZ

              cd $HOME

              # OpenXR/VR support - critical for WiVRn
              export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
              export PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/wivrn/comp_ipc

              # Steam container paths
              export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
              export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata"
              export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$HOME/.local/share/Steam/compatibilitytools.d"

              # OpenVR -> OpenXR translation via xrizer
              export OPENVR_API_PATH="${pkgs.xrizer}/lib/xrizer"
            '';
          };
        };

        # Gamescope - Frame generation/upscaling
        gamescope = {
          enable = true;
          capSysNice = true;
          env = {
            __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
            __GL_SHADER_DISK_CACHE_SIZE = "1073741824";
            __GL_SHADER_DISK_CACHE_PATH = "/var/cache/nvidia-shader-cache";
            __GLX_FORCE_MONO = "0";
            __GL_ALLOW_FXAA_USAGE = "1";
            # HDR configuration - ENABLE_GAMESCOPE_WSI=1 is the standard value
            ENABLE_GAMESCOPE_WSI = "1";
            DXVK_HDR = "1";
          };
          args = [
            "--immediate-flips"
            "--rt"
            "--steam"
            "--xwayland-count 2"
            "--force-composition"
            "--expose-wayland"
          ];
        };

        # nix-ld for running non-NixOS binaries
        nix-ld = {
          enable = true;
          libraries = with pkgs; [
            freetype
            fontconfig
            libpng
            libjpeg
            libtiff
            libpulseaudio
            libvorbis
            libkrb5
            keyutils
            libxcursor
            libxi
            libxinerama
            libxscrnsaver
            vulkan-loader
            vulkan-tools
            stdenv.cc.cc.lib
            pkgsi686Linux.stdenv.cc.cc.lib
            pkgsi686Linux.zlib
            libgcrypt
            libgpg-error
            libusb1
            udev
            libusb-compat-0_1
          ];
        };
      };

      hardware.steam-hardware.enable = true;

      # ============================================================================
      # SYSTEMD - SCX scheduler
      # ============================================================================
      # scx_lavd provides better gaming performance than CFS for mixed workloads
      # It prioritizes latency-sensitive tasks (games) over background work
      systemd.services.scx-lavd = {
        description = "SCX lavd scheduler user-space daemon";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.scx.full}/bin/scx_lavd --autopilot";
          Restart = "on-failure";
          RestartSec = "5s";
          Nice = -20;
          IOSchedulingClass = "realtime";
          IOSchedulingPriority = 7;
        };
      };

      # ============================================================================
      # SERVICES - PipeWire, udev rules
      # ============================================================================
      services = {
        # PipeWire low-latency configuration
        pipewire.extraConfig = lib.mkForce {
          pipewire."99-lowlatency"."context.properties" = {
            "default.clock.min-quantum" = 64;
            "default.clock.max-quantum" = 2048;
          };
          pipewire-pulse."99-lowlatency"."pulse.min.quantum" = "64/48000";
          client."99-lowlatency"."stream.properties"."node.latency" = "64/48000";
        };

        # Disable DualSense/DualShock touchpad to prevent drift in games
        udev.extraRules = ''
          # Disable DualSense (PS5) touchpad
          # Match by device name from parent (ATTRS) and unique touchpad capabilities
          # The touchpad has unique ABS capabilities: 260800000000003
          SUBSYSTEM=="input", ATTRS{name}=="*DualSense*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
          SUBSYSTEM=="input", ATTRS{name}=="*DualShock*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
          # Fallback: Match by capability signature if name matching fails
          SUBSYSTEM=="input", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", ATTRS{capabilities/abs}=="260800000000003", ENV{LIBINPUT_IGNORE_DEVICE}="1"

          # DualSense (PS5) hidraw access for Wine/Proton controller support
          KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"
          # DualSense (PS5) over Bluetooth
          KERNEL=="hidraw*", KERNELS=="*054C:0CE6*", MODE="0660", TAG+="uaccess"
          # DualShock 4 (PS4) hidraw access
          KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", TAG+="uaccess"
          KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", TAG+="uaccess"

          # ============================================================================
          # DualSense Deadzone Calibration (evdev kernel-level)
          # ============================================================================
          # NOTE: linuxconsole package removed from nixpkgs (was evdev-joystick)
          # Deadzone calibration now requires per-game configuration or userspace tools
          # Use SDL_JOYSTICK_AXIS_DEADZONE environment variable for SDL2 games
        '';
      };

      # Create plugdev group for backwards compatibility
      # Note: TAG+="uaccess" (above) provides the same functionality via systemd-logind
      users.groups.plugdev = {};

      systemd.tmpfiles.rules = [
        "d /var/cache/nvidia-shader-cache 0755 root root - -"
        # ldconfig is in glibc.bin output, not glibc.out
        "L /sbin/ldconfig - - - - ${lib.getBin pkgs.glibc}/sbin/ldconfig"
      ];

      # ============================================================================
      # ENVIRONMENT - Session variables, packages, DualSense config
      # ============================================================================
      environment = {
        # Common session variables (gaming + MangoHud defaults)
        sessionVariables = {
          PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
          WINE_FULLSCREEN_FAKE_CAPTURE = "1";
          # Note: SDL_VIDEODRIVER is NOT set - let Steam/Proton auto-detect the best backend
          # This fixes VRChat and other games that benefit from native Wayland support
          # MangoHud default configuration (can be overridden per-game)
          MANGOHUD_CONFIG = "fps,frametime,cpu_stats,gpu_stats,vram,ram,cpu_temp,gpu_temp,core_load,background_alpha=0.5,position=top-left,toggle_hud=Shift_R+F12";
          # Auto-reload GameMode config when launching games
          GAMEMODE_AUTO_RELOAD_CONFIG = "1";
          # SDL2 joystick deadzone (0-100, default 15) - 5% for all joysticks
          # Native DualSense support: SDL2 will use built-in controller mappings
          SDL_JOYSTICK_AXIS_DEADZONE = "5";
        };

        # Common gaming packages
        systemPackages = with pkgs; [
          gamescope
          mangohud
          goverlay
          gamemode
          scx.full
          # linuxconsole  # Package removed from nixpkgs - was evdev-joystick for deadzone calibration
          (pkgs.writeShellScriptBin "launch-game" ''
            #!/usr/bin/env bash
            # launch-game - Wrapper to run games in gaming.slice with GameMode
            # Usage: launch-game [command] [args...]
            #
            # Examples:
            #   launch-game steam
            #   launch-game lutris
            #   launch-game heroic
            #   launch-game /path/to/game executable
            #
            # Per-game configuration via GameMode:
            # Create ~/.config/gamemode.ini with per-game settings:
            #   [game/executable-name]
            #   governor=performance
            #   gpu_optimisations=1

            set -euo pipefail

            # Validate arguments
            if [ $# -eq 0 ]; then
              echo "Usage: launch-game [command] [args...]" >&2
              echo "Launch a game in gaming.slice with GameMode integration" >&2
              echo "" >&2
              echo "Examples:" >&2
              echo "  launch-game steam" >&2
              echo "  launch-game lutris game://12345" >&2
              echo "  launch-game heroic" >&2
              echo "  launch-game /opt/game/bin/game.exe" >&2
              echo "" >&2
              echo "Per-game config: ~/.config/gamemode.ini" >&2
              exit 1
            fi

            # Check if gaming.slice exists
            if ! systemctl show gaming.slice >/dev/null 2>&1; then
              echo "Warning: gaming.slice not found, running without cgroup isolation" >&2
              exec "$@"
            fi

            # Launch the game in gaming.slice with GameMode
            exec systemd-run --user \
              --slice=gaming.slice \
              --property=CPUWeight=1024 \
              --property=IOWeight=1000 \
              --property=Nice=-5 \
              --property=IOSchedulingClass=best-effort \
              --property=IOSchedulingPriority=4 \
              --collect \
              --quiet \
              -- "$@"
          '')
        ];

        etc = {
          # Native SDL2 DualSense support
          # Removed custom SDL2 GameControllerDB to restore native DualSense features
          # Native support enables: haptic feedback, adaptive triggers, gyro, touchpad, LED control
          # Deadzone control: SDL_JOYSTICK_AXIS_DEADZONE env var (set to "5" above)
          # Reference: https://wiki.libsdl.org/SDL2/SupportedControllers
        };
      };

      # ============================================================================
      # MANGOHUD - Performance overlay
      # ============================================================================
      # Note: Configuration is handled via MANGOHUD_CONFIG env var (set in sessionVariables)
      # or ~/.config/MangoHud/MangoHud.conf (can be managed via GOverlay)
    })

    # VR configuration (only when vr.enable = true)
    (mkIf vrCfg.enable {
      # ============================================================================
      # SERVICES - Avahi for WiVRn discovery, WiVRn streaming
      # ============================================================================
      services = {
        # Avahi - Required for WiVRn server discovery
        avahi = {
          enable = true;
          nssmdns4 = true;
          openFirewall = true;
        };

        # WiVRn - Wireless VR Streaming for Quest Headsets
        wivrn = {
          enable = true;
          openFirewall = true;
          defaultRuntime = true;
          autoStart = true;
        };

        # VR device udev rules
        udev.extraRules = ''
          # Oculus Rift
          SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="0181", MODE="0666", TAG+="uaccess"

          # Valve Index / Vive
          SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", TAG+="uaccess"
          SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2102", MODE="0666", TAG+="uaccess"
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0666", TAG+="uaccess"

          # HTC Vive
          SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", ATTR{idProduct}=="2c87", MODE="0666", TAG+="uaccess"
        '';
      };

      # VR firewall ports
      networking.firewall = {
        allowedTCPPorts = [9757];
        allowedUDPPorts = [
          9757
          5353
          9947
          27036
          27031
        ];
      };

      # VR kernel modules
      boot.kernelModules = [
        "usbhid"
        "uvcvideo"
        "nvidia-uvm"
        "hid-sensor-hub"
        "uinput"
      ];

      # VR graphics packages
      hardware.graphics.extraPackages = with pkgs; [
        freetype
        fontconfig
        libpng
        libjpeg
        libtiff
      ];
      # NOTE: extraPackages32 removed - breaks Wayland on multi-NVIDIA

      # ============================================================================
      # ENVIRONMENT - VR session variables and packages
      # ============================================================================
      environment = {
        # VR-specific session variables
        sessionVariables = {
          OPENVR_API_PATH = "${pkgs.xrizer}/lib/xrizer";
        };

        # VR-specific packages
        systemPackages = with pkgs; ([
            wivrn
            openxr-loader
            opencomposite
            openvr
            xrizer
            motoc
            # VR font/graphics dependencies
            freetype
            fontconfig
            libpng
            libjpeg
            libtiff
            ffmpeg
          ]
          # Temporarily disabled nixpkgs-xr packages due to deprecated options
          # ++ optionals (inputs != null && inputs ? nixpkgs-xr) [
          #   inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.oscavmgr
          # ]
          ++ [
            # GPU profile command (merged here to avoid duplicate assignment)
            (pkgs.writeShellScriptBin "gpu-profile" ''
              exec ${./scripts/gpu-profiles/switch-profile} "$@"
            '')
          ]);
      };

      # ============================================================================
      # COMPUTE WORKLOAD MONITOR MODULE
      # ============================================================================
      # Automatically detects workload type (gaming/AI/K8s/mining/idle)
      # and switches GPU profiles accordingly
      # Pauses mining when gaming, AI, or Kubernetes GPU workloads are detected
      # Refactored to dedicated module: modules/system/compute-workload-monitor.nix
      services.compute-workload-monitor.enable = true;

      # ============================================================================
      # GAMEMODE INTEGRATION
      # ============================================================================
      # GameMode provides automatic detection when games start/stop
      # and runs our custom scripts to switch GPU profiles

      # ============================================================================
      # GPU PROFILE COMMANDS
      # ============================================================================
      # Convenient aliases for manual profile switching
      # NOTE: gpu-profile command merged with VR packages above to avoid duplicate assignment
    })

    # CABC Disable configuration (only when disableCabcTriggers.enable = true)
    (mkIf cfg.disableCabcTriggers {
      # ============================================================================
      # DISABLE COLOR MANAGEMENT DAEMON (colord)
      # ============================================================================
      # colord monitors displays and switches ICC profiles, sending HDMI control
      # signals that trigger TV CABC to adjust brightness
      services.colord.enable = mkForce false;

      # ============================================================================
      # DISABLE POWERDEVIL DISPLAY POWER FEATURES
      # ============================================================================
      # PowerDevil sends DPMS signals that can trigger HDMI renegotiation
      environment.etc."xdg/powermanagementprofilesrc".text = ''
        [Profile]
        Actions=undefined

        [AC][BrightnessControl]
        # Disable brightness control to prevent HDMI signals
        enable=false

        [AC][DPMSControl]
        # Disable DPMS to prevent HDMI sleep/wake signals
        enable=false

        [Battery][BrightnessControl]
        enable=false

        [Battery][DPMSControl]
        enable=false
      '';

      # ============================================================================
      # STATIC KDE CONFIGURATION
      # ============================================================================
      # Prevent dynamic color profile switching
      environment.etc."xdg/kdeglobals".text = ''
        [General]
        # Fixed color scheme - no automatic changes
        ColorScheme=Default

        [KDE]
        # Look and feel - lock to prevent theme changes
        LookAndFeelScheme=org.kde.breeze.desktop

        [Colors:Window]
        BackgroundNormal=49,54,59

        [Colors:Selection]
        BackgroundNormal=61,174,233

        [Colors:Button]
        BackgroundNormal=49,54,59

        [Colors:Tooltip]
        BackgroundNormal=49,54,59
      '';

      # Disable KDE color management integration
      environment.plasma6.excludePackages = with pkgs.kdePackages; [
        colord-kde
      ];

      # ============================================================================
      # DISABLE KSCREEN DYNAMIC DISPLAY CHANGES
      # ============================================================================
      # Prevent KScreen from re-negotiating HDMI connection
      environment.etc."xdg/kscreenlockerrc".text = ''
        [Daemon]
        # Disable background monitoring of display changes
        LockEnabled=false
      '';

      environment.etc."xdg/kscreendrc".text = ''
        [General]
        # Disable automatic screen arrangement changes
        ControlCenter=false
      '';

      # ============================================================================
      # SYSTEMD USER UNITS TO BLOCK COLOR MANAGEMENT
      # ============================================================================
      systemd.user.services."disable-colord-triggers" = {
        description = "Disable colord and color profile triggers";
        wantedBy = ["default.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "disable-colord-triggers" ''
            #!/bin/sh
            # Block colord from starting
            systemctl --user mask colord.service 2>/dev/null || true

            # Disable KDE color management integration
            mkdir -p "$HOME/.config"
            echo "[General]" > "$HOME/.config/kdeglobals"
            echo "ColorScheme=Default" >> "$HOME/.config/kdeglobals"
            echo "LookAndFeelScheme=org.kde.breeze.desktop" >> "$HOME/.config/kdeglobals"

            # Disable PowerDevil display power management
            echo "[AC]" > "$HOME/.config/powermanagementprofilesrc"
            echo "[AC][DPMSControl]" >> "$HOME/.config/powermanagementprofilesrc"
            echo "enable=false" >> "$HOME/.config/powermanagementprofilesrc"
            echo "[AC][BrightnessControl]" >> "$HOME/.config/powermanagementprofilesrc"
            echo "enable=false" >> "$HOME/.config/powermanagementprofilesrc"
            echo "[Battery][DPMSControl]" >> "$HOME/.config/powermanagementprofilesrc"
            echo "enable=false" >> "$HOME/.config/powermanagementprofilesrc"
            echo "[Battery][BrightnessControl]" >> "$HOME/.config/powermanagementprofilesrc"
            echo "enable=false" >> "$HOME/.config/powermanagementprofilesrc"
          '';
        };
      };

      # ============================================================================
      # XDG AUTOSTART DISABLE
      # ============================================================================
      # Prevent colord and color management from auto-starting
      environment.etc."xdg/autostart/colord-kde.desktop".text = ''
        [Desktop Entry]
        Hidden=true
        X-GNOME-Autostart-enabled=false
      '';

      # ============================================================================
      # NVIDIA DRIVER SETTINGS
      # ============================================================================
      # Force static colorimetry to prevent HDMI color space changes
      hardware.nvidia.forceFullCompositionPipeline = true;
    })
  ];
}
