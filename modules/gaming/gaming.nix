{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
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
    nativeBuildInputs = [ pkgs.gcc ];
  };
in
{
  options.services.gaming = {
    enable = mkEnableOption "Gaming support (Steam, GameMode, Gamescope)";
    vr = {
      enable = mkEnableOption "VR support (WiVRn, SteamVR, OpenXR)";
      encoder = mkOption {
        type = types.enum [
          "nvenc"
          "x264"
          "av1"
        ];
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
    (mkIf cfg.enable {


      assertions = [
        {
          assertion = cfg.vr.enable -> cfg.vr.refreshRate >= 60 && cfg.vr.refreshRate <= 144;
          message = ''
            Invalid VR refresh rate: ${toString cfg.vr.refreshRate}
            Refresh rate must be between 60 and 144 Hz.
            Recommended values:
              - 72 Hz (entry-level VR)
              - 90 Hz (balanced performance/quality)
              - 120 Hz (high-end VR)
              - 144 Hz (enthusiast-grade VR)
          '';
        }
        {
          assertion = cfg.vr.enable -> (builtins.match "^[0-9]+x[0-9]+$" cfg.vr.resolution) != null;
          message = ''
            Invalid VR resolution format: "${cfg.vr.resolution}"
            Resolution must be in format WIDTHxHEIGHT (per-eye).
            Valid examples:
              - "2160x2160" (default, Quest 2)
              - "2880x2880" (Quest 3)
              - "4096x4096" (high-end)
            Current value: ${cfg.vr.resolution}
          '';
        }
        {
          assertion = cfg.vr.enable -> cfg.vr.encoder == "nvenc" -> (config.hardware.nvidia.enabled or false);
          message = ''
            VR encoder is set to "nvenc" but NVIDIA support is not enabled.
            When using nvenc encoder, ensure:
              hardware.nvidia.enable = true;
            Or switch to CPU encoders:
              services.gaming.vr.encoder = "x264";
              services.gaming.vr.encoder = "av1";
            Current configuration:
              vr.encoder = "${cfg.vr.encoder}"
              hardware.nvidia.enable = ${toString (config.hardware.nvidia.enable or false)}
          '';
        }
      ];


      programs = {
        gamemode = {
          enable = true;
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
                /run/current-system/sw/bin/nvidia-settings -a "[gpu:1]/GpuPowerMizerMode=1" 2>/dev/null || true
                /run/current-system/sw/bin/nvidia-settings -a "[gpu:1]/GPUGraphicsClockOffset[4]=100" 2>/dev/null || true
                /run/current-system/sw/bin/nvidia-settings -a "[gpu:1]/GPUMemoryTransferRateOffset[4]=400" 2>/dev/null || true
                /etc/nixos/scripts/gpu-profiles/gaming.sh 2>/dev/null || true
                /etc/nixos/scripts/gpu-profiles/k8s-mining-pause.sh start 2>/dev/null || true
              ''}";
              end = "${pkgs.writeShellScript "gamemode-end" ''
                ${pkgs.libnotify}/bin/notify-send 'GameMode deactivated' 'Normal performance restored'
                /run/current-system/sw/bin/nvidia-settings -a "[gpu:1]/GpuPowerMizerMode=0" 2>/dev/null || true
                /run/current-system/sw/bin/nvidia-settings -a "[gpu:1]/GPUGraphicsClockOffset[4]=0" 2>/dev/null || true
                /run/current-system/sw/bin/nvidia-settings -a "[gpu:1]/GPUMemoryTransferRateOffset[4]=0" 2>/dev/null || true
                /etc/nixos/scripts/gpu-profiles/ai-inference.sh 2>/dev/null || true
                /etc/nixos/scripts/gpu-profiles/k8s-mining-pause.sh end 2>/dev/null || true
              ''}";
            };
          };
        };
        steam = {
          enable = true;
          fontPackages = with pkgs; [
            noto-fonts
            liberation_ttf
            dejavu_fonts
          ];
          extraCompatPackages = [
          ];
          package = pkgs.steam.override {
            extraLibraries =
              pkgs: with pkgs; [
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
              unset TZ
              cd $HOME
              export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
              export PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/wivrn/comp_ipc
              export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
              export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata"
              export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$HOME/.local/share/Steam/compatibilitytools.d"
              export OPENVR_API_PATH="${pkgs.xrizer}/lib/xrizer"
            '';
          };
        };
        gamescope = {
          enable = true;
          capSysNice = true;
          env = {
            __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
            __GL_SHADER_DISK_CACHE_SIZE = "1073741824";
            __GL_SHADER_DISK_CACHE_PATH = "/var/cache/nvidia-shader-cache";
            __GLX_FORCE_MONO = "0";
            __GL_ALLOW_FXAA_USAGE = "1";
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



      services = {
        pipewire.extraConfig = lib.mkForce {
          pipewire."99-lowlatency"."context.properties" = {
            "default.clock.min-quantum" = 64;
            "default.clock.max-quantum" = 2048;
          };
          pipewire-pulse."99-lowlatency"."pulse.min.quantum" = "64/48000";
          client."99-lowlatency"."stream.properties"."node.latency" = "64/48000";
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
      users.groups.plugdev = { };
      boot.kernelModules = [ "hid_sony" ];
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
          DXVK_FILTER_DEVICE_NAME = "NVIDIA GeForce RTX 3090";
        };
        systemPackages = with pkgs; [
          gamescope
          mangohud
          goverlay
          gamemode
          scx.full
          (pkgs.writeShellScriptBin "launch-game" ''
            #!/usr/bin/env bash
            set -euo pipefail
            if [ $
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


      services = {
        avahi = {
          enable = true;
          nssmdns4 = true;
          openFirewall = true;
        };
        wivrn = {
          enable = true;
          openFirewall = true;
          autoStart = true;
        };
        udev.extraRules = ''
          SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="0181", MODE="0666", TAG+="uaccess"
          SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", TAG+="uaccess"
          SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2102", MODE="0666", TAG+="uaccess"
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0666", TAG+="uaccess"
          SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", ATTR{idProduct}=="2c87", MODE="0666", TAG+="uaccess"
        '';
      };
      networking.firewall = {
        allowedTCPPorts = lib.mkOptionDefault [ 9757 ];
        allowedUDPPorts = lib.mkOptionDefault [
          9757
          5353
          9947
          27036
          27031
        ];
      };
      boot.kernelModules = [
        "usbhid"
        "uvcvideo"
        "nvidia-uvm"
        "hid-sensor-hub"
        "uinput"
      ];
      hardware.graphics.extraPackages = with pkgs; [
        freetype
        fontconfig
        libpng
        libjpeg
        libtiff
      ];


      environment = {
        sessionVariables = {
          OPENVR_API_PATH = "${pkgs.xrizer}/lib/xrizer";
        };
        systemPackages =
          with pkgs;
          (
            [
              wivrn
              openxr-loader
              opencomposite
              openvr
              xrizer
              motoc
              freetype
              fontconfig
              libpng
              libjpeg
              libtiff
              ffmpeg
            ]
            ++ [
              (pkgs.writeShellScriptBin "gpu-profile" ''
                exec ${./scripts/gpu-profiles/switch-profile} "$@"
              '')
            ]
          );
      };


      services.gaming-detection.enable = true;
      services.gpu-profile-manager.enable = true;




    })
  ];
}
