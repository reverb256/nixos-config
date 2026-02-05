# Gaming Module - SteamVR, WiVRn, Lighthouse Tracking, and Motion Tracking
# Enhanced with GameMode, NVENC, Smart Mining Management, and Performance Scheduling
# Complete VR setup for Quest Pro with 4 Tundra trackers
# NVIDIA RTX 3090 optimizations for multiple resolution targets
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
    openFirewall = true;  # Open firewall for wireless VR streaming
    defaultRuntime = true; # Set as default OpenXR runtime
    autoStart = true;     # Start automatically
  };

  # MONADO - Kept for compatibility with some OpenXR applications if needed
  # Primarily using WiVRn for VRChat and Quest support
  services.monado = {
    enable = false;  # Disabled in favor of WiVRn
    defaultRuntime = false;
  };

  # ============================================================================
  # GAMEMODE - CPU/GPU Optimizations
  # ============================================================================
  # ============================================================================
  # GAMEMODE - CPU/GPU Optimizations
  # ============================================================================
  # GAMEMODE - CPU/GPU Optimizations
  # ============================================================================

  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        desiredgov = "performance"; # Use performance governor when entering GameMode
        # GameMode integration with systemd slices
        use_systemd = true;

        # Additional GameMode optimizations
        softrealtime = "auto"; # Use SCHED_ISO when available
        renice = 15; # Increase priority for gaming processes
        ioprio = 0; # Highest I/O priority
      };
      gpu = {
        # CRITICAL: This flag is required for GPU optimizations to work
        apply_gpu_optimisations = "accept-responsibility";

        # NVIDIA Ampere (RTX 3090) specific settings
        nv_powermizer_mode = 1; # Prefer Maximum Performance
        nv_core_clock_mhz_offset = 150; # Slight overclock (+150MHz)
        nv_mem_clock_mhz_offset = 500; # Fixed: Correct parameter name for memory overclock
        # nv_gpu_utilization = "1"; # Removed: Not supported by gamemode

        # Ampere-specific optimizations
        # nv_preclocked_graphics_clock = "1"; # Removed: Not supported by gamemode
        # nv_preclocked_memory_clock = "1"; # Removed: Not supported by gamemode
        # nv_preclocked_video_clock = "1"; # Removed: Not supported by gamemode

        # DLSS and RTX optimizations - these are game-level settings, not gamemode
        # nv_dlss = "1"; # Removed: Not supported by gamemode
        # nv_reflex = "1"; # Removed: Not supported by gamemode
        # nv_api = "1"; # Removed: Not supported by gamemode
      };

      # Custom scripts for GameMode events
      custom = {
        start = "/run/current-system/sw/bin/notify-send 'GameMode activated' 'Performance optimizations enabled'";
        end = "/run/current-system/sw/bin/notify-send 'GameMode deactivated' 'Normal performance restored'";
      };
    };
  };

  # ============================================================================
  # SYSTEMD SLICES - Workload isolation for gaming
  # ============================================================================

  # GameMode service configuration
  systemd.services.gamemode = lib.mkIf config.programs.gamemode.enable {
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

  # gamescope-session service for Wayland gaming (user service)
  # Removed gamescope-session service as it's not needed for basic gaming setup
  # Gamescope can be launched manually or through Steam's launch options

  systemd.slices."gaming.slice" = {
    description = "Gaming applications slice";
    sliceConfig = {
      MemoryHigh = "90%"; # High memory priority for games
      CPUQuota = "95%"; # High CPU priority for games
      CPUAccounting = "yes";
      MemoryAccounting = "yes";
      TasksAccounting = "yes";
      TasksMax = 20000;
      # Critical for NVIDIA Wayland support
      DeviceAllow = "char-226 rw";
      BlockIOAccounting = "yes";
      BlockIOWeight = 1000;
    };
  };

  # ============================================================================
  # STEAM - Full VR Support with NVENC Optimizations
  # ============================================================================
  # MERGED: Single steam configuration with proper package override
  programs.steam = {
    enable = true;
    # Font packages for Steam and Proton (fixes FreeType/Wine issues)
    fontPackages = with pkgs; [
      noto-fonts
      liberation_ttf
      dejavu_fonts
    ];
    # Extra compatibility tools including Proton-GE-RTSP for VRChat
    extraCompatPackages = with pkgs;
      [
      ]
      ++ (
        if inputs != null && inputs ? nixpkgs-xr
        then [
          inputs.nixpkgs-xr.packages."x86_64-linux".proton-ge-rtsp-bin
        ]
        else []
      );
    # Override Steam package with additional libraries and environment fixes
    package = pkgs.steam.override {
      extraLibraries = pkgs:
        with pkgs; [
          freetype
          fontconfig
          libpng
          libjpeg
          libtiff
          # Additional libraries for Proton/Steam
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
        # Fixes timezones on VRChat and other games
        unset TZ
        # Allow Steam to change to user's home directory initially to avoid bwrap errors
        cd $HOME
        # Allows OpenXR runtimes (WiVRn) to be used by Steam/Proton
        export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
        # Enable DXVK async for better performance
        export DXVK_ASYNC=1
        # NVIDIA optimizations
        export __GL_SHADER_DISK_CACHE=1
        export __GL_SHADER_DISK_CACHE_SIZE=1000000000
        # Python compatibility fixes for pressure-vessel
        export PYTHONNOUSERSITE=1
        export PYTHONDONTWRITEBYTECODE=1
        export PYTHONPATH=""
        # Fix sre_parse.TYPE_FLAGS error
        export STEAM_RUNTIME_PYTHON_VERSION=""
        # Pressure-vessel graphics compatibility
        export PRESSURE_VESSEL_LOG_LEVEL=2
        export PRESSURE_VESSEL_FILESYSTEMS_BIND_READONLY=/run/opengl-driver:/run/host/run/opengl-driver
        # NVIDIA + pressure-vessel
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        # Vulkan and NVENC
        export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json:/run/opengl-driver-32/share/vulkan/icd.d/nvidia_icd.json
        export __GL_EXTERNAL_EXTENSIONS=1
        export CUDA_PATH=/run/opengl-driver
        # Steam can find Proton-GE-RTSP
        export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
        export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata"
        export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$HOME/.local/share/Steam/compatibilitytools.d"
        # VRChat specific variables
        export WINE_FULLSCREEN_FAKE_CAPTURE=1
        export DXVK_CONFIG_FILE=/dev/null
        # Additional OpenXR runtime variables for WiVRn
        export OPENXR_ACTIVE_RUNTIME=/nix/store/93gdgwz68nf0ngrkjiazqim4ixv7mz44-wivrn-25.12/lib/wivrn
        # Explicitly set OpenVR API path
        export OPENVR_API_PATH="${pkgs.opencomposite}/lib/opencomposite"
      '';
    };
  };

  # ============================================================================
  # NIX-LD - Critical for Steam and Proton on NixOS
  # https://github.com/NixOS/nix-ld
  # ============================================================================
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Core libraries for Steam/Proton
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
    # 32-bit libraries for Proton
    pkgsi686Linux.stdenv.cc.cc.lib
    pkgsi686Linux.zlib
    # Additional Proton libraries
    libgcrypt
    libgpg-error
    libusb1
    udev
    libusb-compat-0_1
    # VRChat-specific libraries
    openvr
    opencomposite
  ];

  # Enable Steam hardware support for comprehensive controller udev rules
  hardware.steam-hardware.enable = true;

  # Enable Steam networking features (2026 standards)
  programs.steam.remotePlay.openFirewall = true;
  programs.steam.dedicatedServer.openFirewall = true;
  programs.steam.localNetworkGameTransfers.openFirewall = true;

  # ============================================================================
  # STEAM RUNTIME - Additional compatibility setup
  # ============================================================================
  environment.sessionVariables = {
    # Ensure Steam runtime picks up OpenXR
    PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
    # Wine compatibility for VRChat
    WINE_FULLSCREEN_FAKE_CAPTURE = "1";
    # Better GPU offloading for VR apps
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    # For OpenComposite compatibility
    OPENVR_API_PATH = "${pkgs.opencomposite}/lib/opencomposite";
  };

  # ============================================================================
  # ANIME GAME LAUNCHERS (Simplified ezKEa Setup)
  # ============================================================================
  # Only the 4 games you need - direct ezKEa package references
  programs.anime-game-launcher = lib.mkIf (inputs != null && inputs ? ezkea) {
    enable = true;
    package = inputs.ezkea.packages.x86_64-linux.anime-game-launcher;
  };
  programs.honkers-railway-launcher = lib.mkIf (inputs != null && inputs ? ezkea) {
    enable = true;
    package = inputs.ezkea.packages.x86_64-linux.honkers-railway-launcher;
  };
  programs.wavey-launcher = lib.mkIf (inputs != null && inputs ? ezkea) {
    enable = true;
    package = inputs.ezkea.packages.x86_64-linux.wavey-launcher;
  };
  programs.sleepy-launcher = lib.mkIf (inputs != null && inputs ? ezkea) {
    enable = true;
    package = inputs.ezkea.packages.x86_64-linux.sleepy-launcher;
  };

  # ============================================================================
  # WI VRN - Wireless VR Streaming for Quest Pro
  # ============================================================================
  # WiVRn user service (since services.wivrn NixOS module not available)
  systemd.user.services.wivrn = lib.mkForce {
    description = "WiVRn - Wireless VR streaming for Quest Pro";
    after = ["network.target" "pipewire.service"];
    wants = ["pipewire.service"];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.wivrn}/bin/wivrn-server";
      ExecStop = "${pkgs.wivrn}/bin/wivrn-apk stop";
      Restart = "on-failure";
      RestartSec = 5;

      # Environment for Quest Pro with NVENC
      Environment = [
        "WIVRN_LOG=info"
        "WIVRN_ENCODER=nvenc"
        "WIVRN_REFRESH_RATE=90"
        "WIVRN_RESOLUTION=2160x2160"
        "WIVRN_BITRATE=100000000" # 100Mbps
      ];
    };

    # Start automatically when user logs in
    wantedBy = ["default.target"];
  };

  # Enable Avahi for Quest discovery (zephyr VR workstation)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      # Allow user services (like WiVRn) to publish via Avahi
      userServices = true;
    };
    # Security hardening: restrict to wired ethernet only
    allowInterfaces = ["enp38s0"];
    denyInterfaces = ["tailscale0" "wlan*" "docker*" "virbr*"];
    extraConfig = ''
      [wide-area]
      enable-wide-area=no

      [publish]
      disable-user-service-publishing=no
    '';
  };

  # ============================================================================
  # FIREWALL - WiVRn and Lighthouse Support
  # ============================================================================
  networking.firewall = {
    allowedTCPPorts = [9757]; # WiVRn TCP
    allowedUDPPorts = [
      9757 # WiVRn UDP
      5353 # Avahi/mDNS for device discovery
      9947 # Lighthouse base stations
      27036 # SteamVR discovery
      27031 # SteamVR
    ];
  };

  # ============================================================================
  # NVIDIA VR OPTIMIZATIONS - NVENC, Low Latency, VR Ready
  # ============================================================================
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # FIX: FreeType/Font libraries for Proton/Wine (pressure-vessel container)
  # These libraries are placed in /run/opengl-driver/lib where pressure-vessel
  # copies them into the Proton container, fixing "Wine cannot find FreeType" errors
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

  boot.extraModprobeConfig = ''
    # NVIDIA VR optimizations for RTX 3090
    options nvidia "NVreg_RegistryDwords=RMIntrLockingMode=1;NVreg_EnableResizableBar=1;NVreg_EnableGpuFirmware=1"
    options nvidia-uvm "uvm_perf_prefetch_enable=1"
    # Disable CPU frequency scaling for consistent VR performance
    options cpufreq_performance ignore_cpu_freq=1
    # Audio stability - prevent crackling during gaming
    options snd_hda_intel power_save=0
    options snd_hda_intel power_save_controller=N
    # Conservative audio buffer settings
    options snd_hda_intel bdl_pos_adj=0  # Disable buffer position adjustments
    # USB optimization for VR devices
    options usbcore autosuspend=-1
  '';

  # ============================================================================
  # PACKAGES - VR Applications and Tools
  # ============================================================================
  environment.systemPackages = with pkgs;
    [
      # VR runtimes and tools
      wivrn
      openxr-loader
      opencomposite
      openvr

      # SteamVR support
      steam-run

      # LVRA Wiki: xrizer for SteamVR/OpenVR compatibility
      # https://lvra.gitlab.io/docs/distros/nixos/
      xrizer

      # Motion tracking calibration tools
      motoc

      # Eye/Face tracking for Quest Pro (if available)
      (lib.mkIf (inputs != null && inputs ? nixpkgs-xr)
        inputs.nixpkgs-xr.packages."x86_64-linux".oscavmgr)

      # Performance monitoring and optimization tools
      gamescope
      mangohud
      goverlay
      nvtopPackages.full

      # proton-cachyos temporarily disabled
      gamemode
      scx.full

      # Proton/Wine dependencies for VRChat and other games
      freetype
      fontconfig
      libpng
      libjpeg
      libtiff

      # FFmpeg with NVENC support for streaming (using ffmpeg instead of ffmpeg-full to avoid build issues)
      pkgs.ffmpeg

      # Enhanced Claude Code environment (conditional)
    ]
    ++ lib.optionals (inputs != null && inputs ? claude-native) [
      inputs.claude-native.packages."x86_64-linux".default
    ];

  # ANIME GAME LAUNCHERS - ezKEa/aagl-gtk-on-nix overlay
  # Note: Launchers are managed via programs.* options above, not system packages

  # ============================================================================
  # UDEV RULES - VR Device Permissions
  # ============================================================================

  services.udev.extraRules = ''
    # Quest Pro USB rules
    SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="0181", MODE="0666", GROUP="plugdev"

    # Lighthouse base station rules
    SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", GROUP="plugdev"
    SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2102", MODE="0666", GROUP="plugdev"

    # Tundra tracker rules - Valve dongles for SteamVR tracking
    SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2102", MODE="0666", GROUP="plugdev"

    # Tundra tracker individual device rules (if connected directly)
    SUBSYSTEM=="usb", ATTR{idVendor}=="1234", ATTR{idProduct}=="5678", MODE="0666", GROUP="plugdev"

    # Tundra tracker HID interface rules for motion tracking
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0666", GROUP="plugdev"

     # HTC Vive/Valkyrie controllers
     SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", ATTR{idProduct}=="2c87", MODE="0666", GROUP="plugdev"

     # DualSense (PS5) controllers - USB access
     SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="0ce6", MODE="0666", GROUP="plugdev"
     SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="0df2", MODE="0666", GROUP="plugdev"

     # DualSense (PS5) controllers - hidraw access for native support (gyro, haptics, adaptive triggers)
     # Following Valve's official steam-devices rules for proper hidraw access
     KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"
     KERNEL=="hidraw*", KERNELS=="*054C:0CE6*", MODE="0660", TAG+="uaccess"
     KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0660", TAG+="uaccess"
     KERNEL=="hidraw*", KERNELS=="*054C:0DF2*", MODE="0660", TAG+="uaccess"

     # Valve Index controllers
    SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", GROUP="plugdev"
  '';

  # ============================================================================
  # KERNEL MODULES - VR Device Support
  # ============================================================================

  boot.kernelModules = [
    # Required for USB VR devices
    "usbhid"
    "uvcvideo"
    # Required for NVIDIA VR support
    "nvidia-uvm"
    # Required for WiVRn networking
    "wireguard"
    # Required for motion tracking
    "hid-sensor-hub"
    # Required for controller input (Steam Input, DualSense, etc.)
    "uinput"
  ];

  # ============================================================================
  # GAMESCOPE CONFIGURATION - Microcompositor for Gaming
  # ============================================================================

  programs.gamescope = {
    enable = true;
    capSysNice = true; # Allow gamescope to renice itself

    # Environment variables for gamescope
    env = {
      # Vulkan and NVIDIA optimizations
      __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
      __GL_SHADER_DISK_CACHE_SIZE = "1073741824";
      __GL_SHADER_DISK_CACHE_PATH = "/var/cache/nvidia-shader-cache";

      # Ampere optimizations
      __GLX_FORCE_MONO = "0";
      __GL_ALLOW_FXAA_USAGE = "1";

      # HDR support
      ENABLE_HDR_WSI = "11";
      DXVK_HDR = "1";
    };

    # Gamescope configuration - VRR DISABLED, everything else enabled
    args = [
      # NVIDIA Backend (Better compatibility for RTX 3090)
      "--backend sdl"

      # Performance optimizations
      "--immediate-flips" # Lowest latency flips
      "--rt" # Real-time priority

      # HDR enabled (display can handle it, just not VRR)
      "--hdr-enabled"
      "--hdr-itm-enabled" # Inverse tone mapping for better HDR (fixed: added 'd')

      # Steam integration
      "--steam"
      "--xwayland-count 2"

      # Full capabilities maintained
      "--force-composition" # Fixed: removed =auto (deprecated)
      # "--prefer-output" # Commented out: auto value not valid
      "--expose-wayland" # Wayland support
    ];
  };

  # ============================================================================
  # FACE & EYE TRACKING - VRChat Integration
  # ============================================================================

  # Note: OpenSeeFace needs to be installed manually
  # Download from: https://github.com/FaceTracking/OSC-facetracking
  # Ensure nvidia shader cache directory exists
  # Fix ldconfig path for pressure-vessel
  systemd.tmpfiles.rules = [
    "d /var/cache/nvidia-shader-cache 0755 root root - -"
    "L /sbin/ldconfig - - - - ${pkgs.glibc}/sbin/ldconfig"
  ];
}
