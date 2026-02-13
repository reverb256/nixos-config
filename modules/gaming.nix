# Gaming Module - Steam, GameMode, and optional VR support
# VR (WiVRn) is gated by services.gaming.vr.enable option
# Only enable VR on zephyr and nexus (high-end GPUs)
{
  config,
  lib,
  pkgs,
  inputs ? null,
  ...
}:
with lib; let
  cfg = config.services.gaming;
  vrCfg = cfg.vr;
in {
  options.services.gaming = {
    enable = mkEnableOption "Gaming support (Steam, GameMode, gamescope)";

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
      # GAMEMODE - CPU/GPU Optimizations
      # ============================================================================
      programs.gamemode = {
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
            nv_core_clock_mhz_offset = 150;
            nv_mem_clock_mhz_offset = 500;
          };
          custom = {
            start = "/run/current-system/sw/bin/notify-send 'GameMode activated' 'Performance optimizations enabled'";
            end = "/run/current-system/sw/bin/notify-send 'GameMode deactivated' 'Normal performance restored'";
          };
        };
      };

      systemd.services.gamemode = {
        description = "GameMode service";
        wantedBy = ["multi-user.target"];
        after = ["syslog.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          ExecStart = "${pkgs.gamemode}/bin/gamemoded --daemonize";
          ExecStop = "${pkgs.coreutils}/bin/kill -TERM $MAINPID";
          TimeoutStopSec = 10;
          User = "root";
          Group = "root";
        };
      };

      systemd.slices."gaming.slice" = {
        description = "Gaming applications slice";
        sliceConfig = {
          MemoryHigh = "90%";
          CPUQuota = "95%";
          CPUAccounting = "yes";
          MemoryAccounting = "yes";
          TasksAccounting = "yes";
          TasksMax = 20000;
          DeviceAllow = "char-226 rw";
          BlockIOAccounting = "yes";
          BlockIOWeight = 1000;
        };
      };

      # ============================================================================
      # STEAM - Gaming platform
      # ============================================================================
      programs.steam = {
        enable = true;
        fontPackages = with pkgs; [
          noto-fonts
          liberation_ttf
          dejavu_fonts
        ];
        extraCompatPackages = with pkgs;
          optionals (inputs != null && inputs ? nixpkgs-xr) [
            inputs.nixpkgs-xr.packages."x86_64-linux".proton-ge-rtsp-bin
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
            ];
          extraProfile = ''
            unset TZ
            cd $HOME
            export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
            export DXVK_ASYNC=1
            export __GL_SHADER_DISK_CACHE=1
            export __GL_SHADER_DISK_CACHE_SIZE=1000000000
            export PYTHONNOUSERSITE=1
            export PYTHONDONTWRITEBYTECODE=1
            export PYTHONPATH=""
            export STEAM_RUNTIME_PYTHON_VERSION=""
            export PRESSURE_VESSEL_LOG_LEVEL=2
            export PRESSURE_VESSEL_FILESYSTEMS_BIND_READONLY=/run/opengl-driver:/run/host/run/opengl-driver
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export __GL_EXTERNAL_EXTENSIONS=1
            export CUDA_PATH=/run/opengl-driver
            export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
            export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata"
            export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$HOME/.local/share/Steam/compatibilitytools.d"
            export WINE_FULLSCREEN_FAKE_CAPTURE=1
            export OPENVR_API_PATH="${pkgs.opencomposite}/lib/opencomposite"
          '';
        };
      };

      programs.steam.remotePlay.openFirewall = true;
      programs.steam.dedicatedServer.openFirewall = true;
      programs.steam.localNetworkGameTransfers.openFirewall = true;

      # nix-ld for running non-NixOS binaries
      programs.nix-ld.enable = true;
      programs.nix-ld.libraries = with pkgs; [
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

      hardware.steam-hardware.enable = true;

      # Common session variables
      environment.sessionVariables = {
        PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
        WINE_FULLSCREEN_FAKE_CAPTURE = "1";
        __NV_PRIME_RENDER_OFFLOAD = "1";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      };

      # Graphics support
      hardware.graphics.enable = true;
      hardware.graphics.enable32Bit = true;

      # Gamescope configuration
      programs.gamescope = {
        enable = true;
        capSysNice = true;
        env = {
          __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
          __GL_SHADER_DISK_CACHE_SIZE = "1073741824";
          __GL_SHADER_DISK_CACHE_PATH = "/var/cache/nvidia-shader-cache";
          __GLX_FORCE_MONO = "0";
          __GL_ALLOW_FXAA_USAGE = "1";
          ENABLE_HDR_WSI = "11";
          DXVK_HDR = "1";
        };
        args = [
          "--backend sdl"
          "--immediate-flips"
          "--rt"
          "--hdr-enabled"
          "--hdr-itm-enabled"
          "--steam"
          "--xwayland-count 2"
          "--force-composition"
          "--expose-wayland"
        ];
      };

      # Common gaming packages
      environment.systemPackages = with pkgs; [
        gamescope
        mangohud
        goverlay
        nvtopPackages.full
        gamemode
        scx.full
      ];

      systemd.tmpfiles.rules = [
        "d /var/cache/nvidia-shader-cache 0755 root root - -"
        "L /sbin/ldconfig - - - - ${pkgs.glibc}/sbin/ldconfig"
      ];
    })

    # VR configuration (only when vr.enable = true)
    (mkIf vrCfg.enable {
      # ============================================================================
      # WIVRN - Wireless VR Streaming for Quest Headsets
      # ============================================================================
      services.wivrn = {
        enable = true;
        openFirewall = true;
        defaultRuntime = true;
        autoStart = true;
      };

      # VR-specific session variables
      environment.sessionVariables = {
        OPENVR_API_PATH = "${pkgs.opencomposite}/lib/opencomposite";
      };

      # WiVRn user service
      systemd.user.services.wivrn = {
        description = "WiVRn - Wireless VR streaming";
        after = ["network.target" "pipewire.service"];
        wants = ["pipewire.service"];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.wivrn}/bin/wivrn-server";
          ExecStop = "${pkgs.wivrn}/bin/wivrn-apk stop";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [
            "WIVRN_LOG=info"
            "WIVRN_ENCODER=${vrCfg.encoder}"
            "WIVRN_REFRESH_RATE=${toString vrCfg.refreshRate}"
            "WIVRN_RESOLUTION=${vrCfg.resolution}"
            "WIVRN_BITRATE=100000000"
          ];
        };
        wantedBy = ["default.target"];
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

      # VR-specific packages
      environment.systemPackages = with pkgs;
        [
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
        ++ optionals (inputs != null && inputs ? nixpkgs-xr) [
          inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.oscavmgr
        ];

      # VR device udev rules
      services.udev.extraRules = ''
        # VR Headsets and Controllers
        SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="0181", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2102", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0666", GROUP="plugdev"

        # HTC Vive
        SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", ATTR{idProduct}=="2c87", MODE="0666", GROUP="plugdev"

        # Sony PlayStation VR
        SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="0ce6", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="0df2", MODE="0666", GROUP="plugdev"
        KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"
        KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0660", TAG+="uaccess"

        # Valve Index
        SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", GROUP="plugdev"
      '';

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
      hardware.graphics.extraPackages32 = with pkgs.pkgsi686Linux; [
        freetype
        fontconfig
        libpng
        libjpeg
        libtiff
      ];
    })
  ];
}
