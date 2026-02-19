# Gaming Module - Steam, GameMode, and optional VR support
# VR (WiVRn) is gated by services.gaming.vr.enable option
# Only enable VR on zephyr and nexus (high-end GPUs)
#
# IMPORTANT LIMITATIONS (2026-02):
# - SteamVR async reprojection does NOT work on NVIDIA GPUs (no fix available)
#   WiVRn handles frame timing better, but some judder may occur in SteamVR titles
#   See: https://lvra.gitlab.io/docs/distros/nixos/#steamvr
# - xrizer is used for OpenVR compatibility (recommended over OpenComposite)
# - Avahi is required for WiVRn server discovery
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
            # Conservative overclock values - increase gradually if stable
            # Default: 50MHz core, 200MHz memory (safer starting point)
            # Aggressive: 150MHz core, 500MHz memory (may cause instability)
            nv_core_clock_mhz_offset = 50;
            nv_mem_clock_mhz_offset = 200;
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

      # Note: gaming.slice is defined in modules/systemd-slices.nix
      # This ensures consistent resource limits across all hosts

      # ============================================================================
      # STEAM - Gaming platform
      # ============================================================================
      programs.steam = {
        enable = true;
        # SteamOS-style platform optimizations (sysctl, memory management)
        platformOptimizations.enable = true;
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

            # CRITICAL: Fix Vulkan ICD path for NVIDIA on Wayland
            # Steam's pressure-vessel container looks for ICD at wrong path
            export VK_ICD_FILENAMES=/run/host/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json
            export VK_DRIVER_FILES=/run/host/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json
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

      # Common session variables (gaming + MangoHud defaults)
      environment.sessionVariables = {
        PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
        WINE_FULLSCREEN_FAKE_CAPTURE = "1";
        __NV_PRIME_RENDER_OFFLOAD = "1";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        # Force X11 backend for SDL games on Wayland (fixes invisible window issues)
        SDL_VIDEODRIVER = "x11";
        # MangoHud default configuration (can be overridden per-game)
        MANGOHUD_CONFIG = "fps,frametime,cpu_stats,gpu_stats,vram,ram,cpu_temp,gpu_temp,core_load,background_alpha=0.5,position=top-left,toggle_hud=Shift_R+F12";
      };

      # Graphics support
      hardware.graphics.enable = true;
      hardware.graphics.enable32Bit = true;

      # ============================================================================
      # PIPEWIRE LOW-LATENCY - Override desktop.nix for lower gaming latency
      # ============================================================================
      # desktop.nix sets 256/48000 (~5.3ms) which is good for desktop use
      # For gaming, we want 64/48000 (~1.3ms) for minimal audio latency
      # Using mkForce to override desktop.nix's higher values
      services.pipewire.extraConfig = {
        pipewire."99-lowlatency"."context.properties" = {
          "default.clock.min-quantum" = mkForce 64;
          "default.clock.max-quantum" = mkForce 2048;
        };
        pipewire-pulse."99-lowlatency"."pulse.min.quantum" = mkForce "64/48000";
        client."99-lowlatency"."stream.properties"."node.latency" = mkForce "64/48000";
      };

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
          # HDR configuration - ENABLE_GAMESCOPE_WSI=1 is the standard value
          ENABLE_GAMESCOPE_WSI = "1";
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

      # ============================================================================
      # MANGOHUD - Performance overlay for games
      # ============================================================================
      # Note: programs.mangohud is a Home Manager option, not NixOS
      # Configuration is handled via MANGOHUD_CONFIG env var (set in sessionVariables)
      # or ~/.config/MangoHud/MangoHud.conf (can be managed via GOverlay)

      # Common gaming packages
      environment.systemPackages = with pkgs; [
        gamescope
        mangohud
        goverlay
        nvtopPackages.full
        gamemode
        scx.full
      ];

      # Disable DualSense/DualShock touchpad to prevent drift in games
      # The touchpad reports absolute coordinates that can cause camera drift
      # This rule ignores the touchpad at the kernel level (not X11/xinput)
      services.udev.extraRules = ''
        # Disable DualSense (PS5) touchpad
        KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="*DualSense*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
        KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="*DualShock*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
      '';

      systemd.tmpfiles.rules = [
        "d /var/cache/nvidia-shader-cache 0755 root root - -"
        "L /sbin/ldconfig - - - - ${pkgs.glibc}/sbin/ldconfig"
      ];
    })

    # VR configuration (only when vr.enable = true)
    (mkIf vrCfg.enable {
      # ============================================================================
      # AVAHI - Required for WiVRn server discovery
      # ============================================================================
      # Without Avahi, the WiVRn server won't appear in headset discovery
      # and manual IP connection will be required
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };

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
        OPENVR_API_PATH = "${pkgs.xrizer}/lib/xrizer";
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
      # NOTE: DualSense/DualShock rules are NOT needed here - hardware.steam-hardware.enable
      # (set in base gaming config) already provides them via steam-devices-udev-rules
      services.udev.extraRules = ''
        # Oculus Rift
        SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="0181", MODE="0666", GROUP="plugdev"

        # Valve Index / Vive
        SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2102", MODE="0666", GROUP="plugdev"
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0666", GROUP="plugdev"

        # HTC Vive
        SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", ATTR{idProduct}=="2c87", MODE="0666", GROUP="plugdev"
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
