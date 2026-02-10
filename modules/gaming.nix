# Gaming Module - SteamVR, WiVRn, Lighthouse Tracking, and Motion Tracking
# VR setup for Quest Pro with 4 Tundra trackers
{
  config,
  lib,
  pkgs,
  inputs ? null,
  ...
}:
with lib; {
  # ============================================================================
  # WIVRN - Wireless VR Streaming for Quest Headsets (Primary VR Runtime)
  # https://github.com/WiVRn/WiVRn
  # ============================================================================
  services.wivrn = {
    enable = true;
    openFirewall = true;
    defaultRuntime = true;
    autoStart = true;
  };

  services.monado = {
    enable = false;
    defaultRuntime = false;
  };

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

  systemd.services.gamemode = mkIf config.programs.gamemode.enable {
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
  # ANIME GAME LAUNCHERS
  # ============================================================================
  programs.anime-game-launcher.enable = true;
  programs.anime-games-launcher.enable = true;
  programs.honkers-railway-launcher.enable = true;
  programs.honkers-launcher.enable = true;
  programs.wavey-launcher.enable = true;
  programs.sleepy-launcher.enable = true;

  # ============================================================================
  # STEAM - Full VR Support with NVENC Optimizations
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
          xorg.libXcursor
          xorg.libXi
          xorg.libXinerama
          xorg.libXScrnSaver
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
        export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json:/run/opengl-driver-32/share/vulkan/icd.d/nvidia_icd.json
        export __GL_EXTERNAL_EXTENSIONS=1
        export CUDA_PATH=/run/opengl-driver
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
        export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata"
        export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$HOME/.local/share/Steam/compatibilitytools.d"
        export WINE_FULLSCREEN_FAKE_CAPTURE=1
        export DXVK_CONFIG_FILE=/dev/null
        export OPENXR_ACTIVE_RUNTIME=/nix/store/93gdgwz68nf0ngrkjiazqim4ixv7mz44-wivrn-25.12/lib/wivrn
        export OPENVR_API_PATH="${pkgs.opencomposite}/lib/opencomposite"
      '';
    };
  };

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
    xorg.libXcursor
    xorg.libXi
    xorg.libXinerama
    xorg.libXScrnSaver
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
    openvr
    opencomposite
  ];

  hardware.steam-hardware.enable = true;
  programs.steam.remotePlay.openFirewall = true;
  programs.steam.dedicatedServer.openFirewall = true;
  programs.steam.localNetworkGameTransfers.openFirewall = true;

  environment.sessionVariables = {
    PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
    WINE_FULLSCREEN_FAKE_CAPTURE = "1";
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    OPENVR_API_PATH = "${pkgs.opencomposite}/lib/opencomposite";
  };

  # ============================================================================
  # WI VRN - Wireless VR Streaming for Quest Pro
  # ============================================================================
  systemd.user.services.wivrn = mkForce {
    description = "WiVRn - Wireless VR streaming for Quest Pro";
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
        "WIVRN_ENCODER=nvenc"
        "WIVRN_REFRESH_RATE=90"
        "WIVRN_RESOLUTION=2160x2160"
        "WIVRN_BITRATE=100000000"
      ];
    };
    wantedBy = ["default.target"];
  };

  # ============================================================================
  # FIREWALL - WiVRn and Lighthouse Support
  # ============================================================================
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

  # ============================================================================
  # NVIDIA VR OPTIMIZATIONS
  # ============================================================================
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
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

  # ============================================================================
  # PACKAGES - VR Applications and Tools
  # ============================================================================
  environment.systemPackages = with pkgs;
    [
      wivrn
      openxr-loader
      opencomposite
      openvr
      steam-run
      xrizer
      motoc
      gamescope
      mangohud
      goverlay
      nvtopPackages.full
      gamemode
      scx.full
      freetype
      fontconfig
      libpng
      libjpeg
      libtiff
      pkgs.ffmpeg
      # ScopeBuddy dependencies
      jq
      wlr-randr
    ]
    ++ optionals (inputs != null && inputs ? claude-native) [
      inputs.claude-native.packages."x86_64-linux".default
    ]
    ++ optionals (inputs != null && inputs ? nixpkgs-xr) [
      inputs.nixpkgs-xr.packages.${pkgs.system}.oscavmgr
    ];

  # ============================================================================
  # UDEV RULES - VR Device Permissions
  # ============================================================================
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="0181", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2102", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="1234", ATTR{idProduct}=="5678", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", ATTR{idProduct}=="2c87", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="0ce6", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="0df2", MODE="0666", GROUP="plugdev"
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"
    KERNEL=="hidraw*", KERNELS=="*054C:0CE6*", MODE="0660", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0660", TAG+="uaccess"
    KERNEL=="hidraw*", KERNELS=="*054C:0DF2*", MODE="0660", TAG+="uaccess"
    SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", GROUP="plugdev"
  '';

  boot.kernelModules = [
    "usbhid"
    "uvcvideo"
    "nvidia-uvm"
    "wireguard"
    "hid-sensor-hub"
    "uinput"
  ];

  # ============================================================================
  # GAMESCOPE CONFIGURATION
  # ============================================================================
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

  systemd.tmpfiles.rules = [
    "d /var/cache/nvidia-shader-cache 0755 root root - -"
    "L /sbin/ldconfig - - - - ${pkgs.glibc}/sbin/ldconfig"
  ];
}
