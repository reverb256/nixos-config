{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.gaming;
  vrCfg = cfg.vr;
  set-evdev-deadzone = pkgs.stdenv.mkDerivation {
    pname = "set-evdev-deadzone";
    version = "1.0.0";
    src = ./files;
    buildPhase = ''
      gcc -O2 -Wall -o set-evdev-deadzone set-evdev-deadzone.c
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp set-evdev-deadzone $out/bin/
    '';
    nativeBuildInputs = [pkgs.gcc];
  };
in {
  options.services.gaming = {
    enable = mkEnableOption "Gaming support (Steam, GameMode, Gamescope)";
    vr.enable = mkEnableOption "VR support (WiVRn, SteamVR, OpenXR)";
  };
  config = mkMerge [
    (mkIf cfg.enable {
      programs = {
        gamemode = {
          enable = lib.mkDefault true;
          settings = {
            general = {
              desiredgov = "performance";
              use_systemd = true;
              softrealtime = "auto";
              renice = 15;
              ioprio = 1;
            };
            custom = {
              start = "${pkgs.writeShellScript "gamemode-start" ''
                ${pkgs.libnotify}/bin/notify-send 'GameMode activated' 'Performance optimizations enabled'
                /etc/nixos/scripts/gpu-profiles/gaming.sh 2>/dev/null || true
                /etc/nixos/scripts/gpu-profiles/k8s-mining-pause.sh start 2>/dev/null || true
                /etc/nixos/scripts/gpu-profiles/k8s-ai-pause.sh start 2>/dev/null || true
              ''}";
              end = "${pkgs.writeShellScript "gamemode-end" ''
                ${pkgs.libnotify}/bin/notify-send 'GameMode deactivated' 'Normal performance restored'
                /etc/nixos/scripts/gpu-profiles/ai-inference.sh 2>/dev/null || true
                /etc/nixos/scripts/gpu-profiles/k8s-mining-pause.sh end 2>/dev/null || true
                /etc/nixos/scripts/gpu-profiles/k8s-ai-pause.sh end 2>/dev/null || true
              ''}";
            };
          };
        };
        steam = {
          enable = lib.mkDefault true;
          fontPackages = with pkgs; [
            noto-fonts
            liberation_ttf
            dejavu_fonts
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
                # 32-bit libs for Proton VR games
                pkgsi686Linux.stdenv.cc.cc.lib
                pkgsi686Linux.vulkan-loader
                pkgsi686Linux.zlib
                pkgsi686Linux.libpng
                pkgsi686Linux.libjpeg
                pkgsi686Linux.SDL2
              ];
            extraProfile = ''
              unset TZ
              cd $HOME
              export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
              export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
              export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata"
              export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$HOME/.local/share/Steam/compatibilitytools.d"
            '';
          };
        };
        gamescope = {
          capSysNice = true;
          env = {
            __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
            __GL_SHADER_DISK_CACHE_SIZE = "1073741824";
            __GL_SHADER_DISK_CACHE_PATH = "/var/cache/nvidia-shader-cache";
            __GLX_FORCE_MONO = "0";
            __GL_ALLOW_FXAA_USAGE = "1";
            ENABLE_GAMESCOPE_WSI = "1";
            __GL_SYNC_TO_VBLANK = "0";
            DXVK_HDR = "1";
          };
          args = [
            "--immediate-flips"
            "--rt"
            "--steam"
            "--xwayland-count 2"
            "--expose-wayland"
            "--prefer-vk-device 10de:2204"
          ];
        };
        nix-ld = {
          enable = lib.mkDefault true;
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
      hardware.steam-hardware.enable = lib.mkDefault true;

      services = {
        pipewire.extraConfig = lib.mkForce {
          pipewire."99-lowlatency"."context.properties" = {
            "default.clock.min-quantum" = 1024;
            "default.clock.max-quantum" = 2048;
          };
          pipewire-pulse."99-lowlatency"."pulse.min.quantum" = "1024/48000";
          client."99-lowlatency"."stream.properties"."node.latency" = "1024/48000";
        };
        udev.extraRules = ''
          SUBSYSTEM=="input", ATTRS{name}=="Sony Interactive Entertainment DualSense Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
          SUBSYSTEM=="input", ATTRS{name}=="*DualSense*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
          SUBSYSTEM=="input", ATTRS{name}=="*DualShock*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
          SUBSYSTEM=="input", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", ATTRS{capabilities/abs}=="260800000000003", ENV{LIBINPUT_IGNORE_DEVICE}="1"
          KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"
          KERNEL=="hidraw*", KERNELS=="*054C:0CE6*", MODE="0660", TAG+="uaccess"
          KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", TAG+="uaccess"
          KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", TAG+="uaccess"


        '';
      };
      users.groups.plugdev = {};
      boot.kernelModules = ["hid_sony"];
      systemd.tmpfiles.rules = [
        "d /var/cache/nvidia-shader-cache 0755 root root - -"
        "L /sbin/ldconfig - - - - ${lib.getBin pkgs.glibc}/sbin/ldconfig"
      ];

      environment = {
        sessionVariables = {
          PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
          WINE_FULLSCREEN_FAKE_CAPTURE = "1";
          MANGOHUD_CONFIG = "fps,frametime,cpu_stats,gpu_stats,vram,ram,cpu_temp,gpu_temp,core_load,background_alpha=0.5,position=top-left,toggle_hud=Shift_R+F12";
          GAMEMODE_AUTO_RELOAD_CONFIG = "1";
          SDL_JOYSTICK_AXIS_DEADZONE = "30";
          SDL_GAMECONTROLLERDB = "/etc/sdl2-dualsense-db";
        };
        systemPackages = with pkgs; [
          gamescope
          mangohud
          goverlay
          gamemode
          scx.full
          # Hoyoverse game launchers (from ezKEA AAGL flake)
          an-anime-game-launcher
          honkers-railway-launcher
          # Mining pause/resume for desktop launcher
          (pkgs.writeShellScriptBin "mining-pause" ''
            exec /etc/nixos/scripts/gpu-profiles/k8s-mining-pause.sh start
          '')
          (pkgs.writeShellScriptBin "mining-resume" ''
            exec /etc/nixos/scripts/gpu-profiles/k8s-mining-pause.sh end
          '')
          (pkgs.makeDesktopItem {
            name = "mining-pause";
            desktopName = "Mining Pause";
            comment = "Pause all GPU mining on this host";
            icon = "media-playback-pause";
            exec = "mining-pause";
            categories = ["System"];
            terminal = false;
          })
          (pkgs.makeDesktopItem {
            name = "mining-resume";
            desktopName = "Mining Resume";
            comment = "Resume all GPU mining on this host";
            icon = "media-playback-start";
            exec = "mining-resume";
            terminal = false;
          })
          (pkgs.writeShellScriptBin "launch-game" ''
            #!/usr/bin/env bash
            set -euo pipefail
            if [ ''$# -lt 1 ]; then
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
            if ! systemctl show gaming.slice >/dev/null 2>&1; then
              echo "Warning: gaming.slice not found, running without cgroup isolation" >&2
              exec "$@"
            fi
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
          "sdl2-dualsense-db".text = ''
            0300000054c0ce60000000000000000,DualSense Wireless Controller,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,misc1:b1,paddle1:b11,paddle2:b12,paddle3:b13,paddle4:b14,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,Touchpad:b15,x:b2,y:b3,platform:Linux,
            0500000054c0ce60000000000000000,DualSense Wireless Controller,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,misc1:b1,paddle1:b11,paddle2:b12,paddle3:b13,paddle4:b14,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,Touchpad:b15,x:b2,y:b3,platform:Linux,
            0300000054c00000921000000000000,DualSense Wireless Controller,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,platform:Linux,
            0300000054c00000921000016000000,DualSense Wireless Controller,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,platform:Linux,
            0300000054c00000921000000010000,DualSense Wireless Controller,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,platform:Linux,
          '';
          "gamemode.ini".text = lib.mkForce ''
            [general]
            desiredgov = performance
          '';
        };
      };
    })
    (mkIf vrCfg.enable {
      # WiVRn OpenXR streaming — upstream module handles runtime
      # registration, avahi, firewall, and OpenComposite paths
      services.wivrn = {
        enable = lib.mkDefault true;
        openFirewall = true;
        autoStart = false;
        highPriority = true;
        steam.enable = lib.mkDefault true;
        steam.importOXRRuntimes = true;
        package = pkgs.wivrn.override {
          cudaSupport = true;
        };
        config.enable = lib.mkDefault true;
        config.json = {
          encoder = {
            encoder = "nvenc";
            codec = "h265";
          };
          bit-depth = 10;
          use-steamvr-lh = true;
          hid-forwarding = true;
        };
        monadoEnvironment = {
          XRT_COMPOSITOR_COMPUTE = "1";
          U_PACING_COMP_MIN_TIME_MS = "5";
        };
      };

      # UDEV rules for Lighthouse/Valve/HTC/Meta devices
      services.udev.extraRules = ''
        SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="0181", MODE="0666", TAG+="uaccess"
        SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", TAG+="uaccess"
        SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2102", MODE="0666", TAG+="uaccess"
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0666", TAG+="uaccess"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", ATTR{idProduct}=="2c87", MODE="0666", TAG+="uaccess"
      '';

      # ntsync for Proton VR game compatibility (kernel 6.14+)
      boot.kernelModules = [
        "usbhid"
        "uvcvideo"
        "nvidia-uvm"
        "hid-sensor-hub"
        "uinput"
        "ntsync"
      ];

      # GPU workload detection and profile management
      services.gaming-detection.enable = lib.mkDefault true;
      services.gpu-profile-manager.enable = lib.mkDefault true;

      environment = {
        systemPackages = with pkgs;
          [
            xrizer
            opencomposite
            openxr-loader
            openvr
            motoc
            wayvr
            android-tools
            ffmpeg
          ]
          ++ [
            (pkgs.writeShellScriptBin "gpu-profile" ''
              exec ${./scripts/gpu-profiles/switch-profile} "$@"
            '')
          ];
      };
    })
  ];
}
