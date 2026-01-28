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
  # GAMEMODE - CPU/GPU Optimizations
  # ============================================================================

  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        desiredgov = "performance"; # Use performance governor when entering GameMode
        # REMOVE: inhibit_screensaver = true; # INVALID - causes configuration errors
        # REMOVE: require_display = true; # PROBLEMATIC with Wayland - causes hangs
        # GameMode integration with systemd slices
        use_systemd = true;

        # Additional GameMode optimizations
        softrealtime = "auto"; # Use SCHED_ISO when available
        renice = 15; # Increase priority for gaming processes
        ioprio = 0; # Highest I/O priority
      };
      gpu = {
        # NVIDIA Ampere (RTX 3090) specific settings
        nv_powermizer_mode = 1; # Prefer Maximum Performance
        nv_core_clock_mhz_offset = 150; # Slight overclock (+150MHz)
        nv_memory_transfer_rate_offset = 500; # Ampere memory overclock (+500MHz)
        nv_gpu_utilization = "1"; # Enable GPU utilization monitoring

        # Ampere-specific optimizations
        nv_preclocked_graphics_clock = "1"; # Enable preclocked graphics clock
        nv_preclocked_memory_clock = "1"; # Enable preclocked memory clock
        nv_preclocked_video_clock = "1"; # Enable preclocked video clock

        # DLSS and RTX optimizations for Ampere (RTX 3090)
        nv_dlss = "1"; # Enable DLSS if supported by game
        nv_reflex = "1"; # Enable NVIDIA Reflex for competitive gaming
        nv_api = "1"; # Enable NVIDIA API
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
  systemd.services.gamemode = mkIf config.programs.gamemode.enable {
    description = "GameMode service";
    wantedBy = ["multi-user.target"];
    after = ["syslog.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${pkgs.gamemode}/bin/gamemoded --daemonize";
      ExecStop = "${pkgs.gamemode}/bin/gamemoded --kill";
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
  programs.steam = {
    enable = true;
    extraCompatPackages = with pkgs;
      [
      ]
      ++ (if inputs != null then [
        inputs.nixpkgs-xr.packages."x86_64-linux".proton-ge-rtsp-bin
      ] else []);
  };

  # ============================================================================
  # ANIME GAME LAUNCHERS (Simplified ezKEa Setup)
  # ============================================================================
  # Only the 4 games you need - direct ezKEa package references
  programs.anime-game-launcher = lib.mkIf (inputs != null) {
    enable = true;
    package = inputs.ezkea.packages.x86_64-linux.anime-game-launcher;
  };
  programs.honkers-railway-launcher = lib.mkIf (inputs != null) {
    enable = true;
    package = inputs.ezkea.packages.x86_64-linux.honkers-railway-launcher;
  };
  programs.wavey-launcher = lib.mkIf (inputs != null) {
    enable = true;
    package = inputs.ezkea.packages.x86_64-linux.wavey-launcher;
  };
  programs.sleepy-launcher = lib.mkIf (inputs != null) {
    enable = true;
    package = inputs.ezkea.packages.x86_64-linux.sleepy-launcher;
  };

  # ============================================================================
  # WI VRN - Wireless VR Streaming for Quest Pro
  # ============================================================================
  services.wivrn = {
    enable = true;
    openFirewall = true;
    defaultRuntime = true;
    config.enable = true;
    config.json = {
      # Quest Pro specific optimizations for 90Hz target
      device = {
        name = "Quest Pro";
        type = "quest_pro";
        # High resolution for Quest Pro at 90Hz
        resolution = "2160x2160"; # Max Quest Pro resolution per eye
        refresh_rate = 90;
        # RTX 3090 NVENC optimization
        encoder = {
          backend = "nvenc";
          preset = "p7"; # High quality preset
          tune = "ll"; # Low latency for VR
          rc = "vbr"; # Variable bitrate
          bitrate = 100000; # 100Mbps for Quest Pro
          max_bitrate = 120000;
          min_bitrate = 80000;
          # NVENC specific optimizations for RTX 3090
          nvenc = {
            quality = "hq";
            enable_psy = true;
            rc_lookahead = 32;
            spatial_aq = true;
            temporal_aq = true;
          };
        };
      };

      # Streaming optimizations for RTX 3090 at 90Hz
      stream = {
        codec = "hevc"; # HEVC for better compression at 90Hz
        targetBitrate = 150; # Optimized bitrate for RTX 3090 at 90Hz (Mbps)
        spatial = true; # Enable spatial encoding
        temporal = true; # Enable temporal encoding
        encoder = "nvenc"; # Use NVIDIA NVENC for hardware acceleration
        postprocess = true; # Enable post-processing
      };

      # Network optimizations for 90Hz streaming
      network = {
        port = 9757;
        portRange = [9757 9760];
        udp = true;
        tcp = true;
        # RTSP streaming support
        rtsp = {
          enabled = true;
          port = 7889;
          path = "/wivrn";
        };
      };

      # Quest Pro display settings
      display = {
        forceColorSpace = "sRGB";
        forceColorRange = "Full";
      };

      # SteamVR lighthouse driver support for Tundra trackers
      # Enable SteamVR tracked devices support (lighthouse base stations)
      "steamvr-enabled" = true;

      # Lighthouse discovery wait time (ms) - allow devices to be discovered
      "lh-discover-wait-ms" = 5000;

      # Enable lighthouse tracking for external devices
      "lighthouse-enabled" = true;

      # Base station configuration for 2.0 base stations
      "lighthouse-base-stations" = 2;

      # Tundra tracker support via lighthouse
      "tundra-trackers-enabled" = true;

      # Discovery timeout for lighthouse devices
      "lighthouse-discovery-timeout" = 10000;
    };
  };

  # ============================================================================
  # FIREWALL - VR Device and Lighthouse Support
  # ============================================================================
  networking.firewall = {
    allowedTCPPorts = [9757]; # WiVRn
    allowedUDPPorts = [
      9757 # WiVRn
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
  environment.systemPackages = with pkgs; [
    # VR runtimes and tools
    wivrn
    openxr-loader

    # SteamVR support
    steam-run

    # Motion tracking calibration tools
    motoc

    # Performance monitoring and optimization tools
    gamescope
    mangohud
    goverlay
    nvtopPackages.full

    # proton-cachyos temporarily disabled
    gamemode
    scx.full

    # Enhanced Claude Code environment
    inputs.claude-native.packages."x86_64-linux".default

    # FFmpeg with NVENC support for streaming
    pkgs.ffmpeg-full

    # FFmpeg with NVENC support for streaming
    pkgs.ffmpeg-full

    # ANIME GAME LAUNCHERS - ezKEa/aagl-gtk-on-nix overlay
    # Note: Launchers are managed via programs.* options above, not system packages
  ];


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

     # DualSense (PS5) controllers - USB access only, let Wine handle hidraw
     SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="0ce6", MODE="0666", GROUP="plugdev"
     SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="0df2", MODE="0666", GROUP="plugdev"

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
      "--hdr-itm-enable" # Inverse tone mapping for better HDR

      # Steam integration
      "--steam"
      "--xwayland-count 2"

      # Full capabilities maintained
      "--force-composition-pipeline=auto"
      "--prefer-output=auto"
      "--expose-wayland" # Wayland support
    ];
  };

  # ============================================================================
  # FACE & EYE TRACKING - VRChat Integration
  # ============================================================================

  # Note: OpenSeeFace needs to be installed manually
  # Download from: https://github.com/FaceTracking/OSC-facetracking
  # Configure OSC output to port 9000 for VRChat compatibility

  # Custom Proton-GE-RTSP configuration for VRChat
  programs.steam.package = pkgs.steam.override {
    extraProfile = ''
      # Fixes timezones on VRChat
      unset TZ
      # Allows Monado to be used
      export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
      # Optimized for NVENC
      export PROTON_USE_WINED3D=0
      export DXVK_ASYNC=1
      # Custom Proton-GE-RTSP support
      export PROTON_USE_DXVK=1
      
    '';
  };

  # ============================================================================
  # ASSERTIONS - VR Configuration Validation
  # ============================================================================
  # ASSERTIONS - VR Configuration Validation
  # ============================================================================

  # Enable Avahi for device discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  assertions = [
    {
      assertion = config.programs.steam.enable;
      message = "Steam must be enabled for VR support";
    }
    {
      assertion = config.services.wivrn.enable;
      message = "WiVRn must be enabled for VR support";
    }
    {
      assertion = config.hardware.nvidia.package != null;
      message = "NVIDIA drivers are required for optimal VR performance";
    }
  ];

  # Ensure nvidia shader cache directory exists
  systemd.tmpfiles.rules = [
    "d /var/cache/nvidia-shader-cache 0755 root root - -"
  ];
}
