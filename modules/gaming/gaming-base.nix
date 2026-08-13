# Gaming base configuration — Steam, GameMode, Gamescope, MangoHud, nix-ld.
# Extracted from modules/gaming/gaming.nix on 2026-07-29
# per Phase 3 de-monolith plan.
#
# Contains: assertions, programs (gamemode/steam/gamescope/nix-ld),
# hardware, services (pipewire/udev), environment (sessionVariables,
# systemPackages, etc files).
#
# VR configuration lives in ./gaming-vr.nix (gated by services.gaming.vr.enable).
{ config, lib, pkgs, ... }:
with lib; let cfg = config.services.gaming;
in mkIf cfg.enable {
  # ASSERTIONS
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
          services.gaming.vr.encoder = "x264";  # CPU-based
          services.gaming.vr.encoder = "av1";    # CPU-based, newer
        Current configuration:
          vr.encoder = "${cfg.vr.encoder}"
          hardware.nvidia.enable = ${toString (config.hardware.nvidia.enable or false)}
      '';
    }
  ];

  # PROGRAMS - GameMode, Steam, Gamescope, nix-ld
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
            gaming_gpu=$(/run/current-system/sw/bin/nvidia-smi --query-gpu=uuid,name --format=csv,noheader,nounits 2>/dev/null | awk -F', ' '$2 ~ /RTX 3090/ {print $1; exit}')
            if [ -n "$gaming_gpu" ]; then
              /run/current-system/sw/bin/nvidia-settings -a "[gpu:$gaming_gpu]/GpuPowerMizerMode=1" 2>/dev/null || true
              /run/current-system/sw/bin/nvidia-settings -a "[gpu:$gaming_gpu]/GPUGraphicsClockOffset[4]=100" 2>/dev/null || true
              /run/current-system/sw/bin/nvidia-settings -a "[gpu:$gaming_gpu]/GPUMemoryTransferRateOffset[4]=400" 2>/dev/null || true
            fi
            # Nexus intentionally keeps PeakMiner and its declared power profile
            # active while Gamescope and games run concurrently. Do not let the
            # shared GameMode hook rewrite its clocks/power on that host.
            ${lib.optionalString (config.networking.hostName != "nexus") "/etc/nixos/scripts/gpu-profiles/gaming.sh 2>/dev/null || true"}
          ''}";
          end = "${pkgs.writeShellScript "gamemode-end" ''
            ${pkgs.libnotify}/bin/notify-send 'GameMode deactivated' 'Normal performance restored'
            gaming_gpu=$(/run/current-system/sw/bin/nvidia-smi --query-gpu=uuid,name --format=csv,noheader,nounits 2>/dev/null | awk -F', ' '$2 ~ /RTX 3090/ {print $1; exit}')
            if [ -n "$gaming_gpu" ]; then
              /run/current-system/sw/bin/nvidia-settings -a "[gpu:$gaming_gpu]/GpuPowerMizerMode=0" 2>/dev/null || true
              /run/current-system/sw/bin/nvidia-settings -a "[gpu:$gaming_gpu]/GPUGraphicsClockOffset[4]=0" 2>/dev/null || true
              /run/current-system/sw/bin/nvidia-settings -a "[gpu:$gaming_gpu]/GPUMemoryTransferRateOffset[4]=0" 2>/dev/null || true
            fi
            ${lib.optionalString (config.networking.hostName != "nexus") "/etc/nixos/scripts/gpu-profiles/ai-inference.sh 2>/dev/null || true"}
          ''}";
        };
      };
    };
    # Cyberpunk 2077 (appid 1091500) — launch options REQUIRED on this host:
    #   PROTON_ENABLE_WAYLAND=1 VKD3D_VULKAN_DEVICE=0 %command% --launcher-skip -skipStartScreen
    # Rationale (2026-08-03, NVIDIA 610.43.x + Wayland):
    #   - Without --launcher-skip, REDprelauncher -> game chain crashes on NixOS
    #     (nixpkgs #162036). Skipping the launcher is the #1 documented Linux fix.
    #   - PROTON_ENABLE_WAYLAND=1 gives vkd3d-proton a native Wayland surface
    #     instead of XWayland (swapchain "Failed to initialize viewport" class).
    #   - VKD3D_VULKAN_DEVICE=0 pins the RTX 3090 (display-attached) on this
    #     dual-GPU host. Matches the PoE2 (2694490) recipe in Steam userdata.
    # These are per-game Steam user state (localconfig.vdf), so they cannot be
    # declared here — set them in Steam: Properties -> Launch Options.
    steam = {
      enable = true;
      protontricks.enable = true;
      extest.enable = true;
      remotePlay.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
      fontPackages = with pkgs; [
        noto-fonts
        liberation_ttf
        dejavu_fonts
      ];
      # Steam runs in an FHS sandbox — host PATH packages are NOT visible inside.
      # Wiki + nixpkgs#389142: gamescope / gamemode / WSI must be in the Steam env
      # or launch options that call them fail (libgamemode.so missing, no gamescope).
      # NOTE: `steam.override.extraPkgs` is valid per nixpkgs steam module
      # (maps to extraPackages); only `extraLibraries` is invalid.
      extraPackages = with pkgs; [
        gamescope
        gamescope-wsi
        pkgsi686Linux.gamescope-wsi  # 32-bit for Proton Wine
        gamemode
        mangohud
        libXcursor libXi libXinerama libXScrnSaver libpng libpulseaudio libvorbis
        stdenv.cc.cc.lib libkrb5 keyutils
      ];
      extraCompatPackages = [
        pkgs.proton-ge-bin
        pkgs.proton-ge-rtsp
      ];
      package = pkgs.steam.override {
        extraLibraries = pkgs: with pkgs; [
          freetype fontconfig libpng libjpeg libtiff
          vulkan-loader vulkan-tools
          libxcursor libxi libxinerama libxscrnsaver
          libpulseaudio libvorbis stdenv.cc.cc.lib
          libkrb5 keyutils libcap SDL2
          # gamemode client lib for gamemoderun inside the FHS (nixpkgs#389142)
          gamemode
          gamescope gamescope-wsi
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
      # Official wiki: HDR needs the FROG WSI layer (nixpkgs PR #523394).
      # Without this, ENABLE_GAMESCOPE_WSI=1 is a no-op — layer never loads.
      enableWsi = true;
      # Nested + Steam overlay: CAP_SYS_NICE can break overlay hook (gamescope#1225).
      # Keep true for RT scheduling; if overlay dies under nested HDR, set false.
      capSysNice = true;
      env = {
        __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
        __GL_SHADER_DISK_CACHE_SIZE = "1073741824";
        __GL_SHADER_DISK_CACHE_PATH = "/var/cache/nvidia-shader-cache";
        __GLX_FORCE_MONO = "0";
        __GL_ALLOW_FXAA_USAGE = "1";
        ENABLE_GAMESCOPE_WSI = "1";
        DXVK_HDR = "1";
        PROTON_ENABLE_HDR = "1";
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
        freetype fontconfig libpng libjpeg libtiff
        libpulseaudio libvorbis libkrb5 keyutils
        libxcursor libxi libxinerama libxscrnsaver
        vulkan-loader vulkan-tools stdenv.cc.cc.lib
        pkgsi686Linux.stdenv.cc.cc.lib pkgsi686Linux.zlib
        libgcrypt libgpg-error libusb1 udev libusb-compat-0_1
      ];
    };
  };

  hardware.steam-hardware.enable = true;

  # SERVICES - PipeWire, udev rules
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

  users.groups.plugdev = {};

  # GameMode runs inside the autologin UWSM session, which has no interactive
  # polkit agent. Permit its four performance-helper actions for active users;
  # inactive sessions remain denied instead of granting a blanket polkit rule.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "com.feralinteractive.GameMode.cpu-helper" ||
          action.id == "com.feralinteractive.GameMode.governor-helper" ||
          action.id == "com.feralinteractive.GameMode.gpu-helper" ||
          action.id == "com.feralinteractive.GameMode.procsys-helper") {
        return subject.active ? polkit.Result.YES : polkit.Result.NO;
      }
    });
  '';

  boot.kernelModules = ["hid_sony"];
  systemd.tmpfiles.rules = [
    "d /var/cache/nvidia-shader-cache 0755 root root - -"
    "L /sbin/ldconfig - - - - ${lib.getBin pkgs.glibc}/sbin/ldconfig"
  ];

  # ENVIRONMENT
  environment = {
    sessionVariables = {
      PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
      WINE_FULLSCREEN_FAKE_CAPTURE = "1";
      MANGOHUD_CONFIG = "fps,frametime,cpu_stats,gpu_stats,vram,ram,cpu_temp,gpu_temp,core_load,background_alpha=0.5,position=top-left,toggle_hud=Shift_R+F12";
      GAMEMODE_AUTO_RELOAD_CONFIG = "1";
      SDL_JOYSTICK_AXIS_DEADZONE = "30";
      SDL_GAMECONTROLLERDB = "/etc/sdl2-dualsense-db";
      DXVK_FILTER_DEVICE_NAME = "NVIDIA GeForce RTX 3090";
      PROTON_ENABLE_NVAPI = "1";
      DXVK_ENABLE_NVAPI = "1";
    };
    systemPackages = with pkgs; [
      gamescope mangohud goverlay gamemode scx.full protonup-qt
      (pkgs.writeShellScriptBin "launch-game" ''
        #!/usr/bin/env bash
        set -euo pipefail
        if [ $# -eq 0 ]; then
          echo "Usage: launch-game [command] [args...]" >&2
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
}
