{pkgs, ...}: {
  # ============================================================================
  # KERNEL CONFIGURATION - Force ZEN kernel for gaming and mining performance
  # ============================================================================
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # NVIDIA configuration for RTX 3090 (use proprietary drivers with ZEN kernel)
  hardware.nvidia = {
    package = pkgs.linuxPackages_zen.nvidiaPackages.stable;
    modesetting.enable = true;
    open = false;
  };
    nixpkgs.config.allowUnfree = true;
    nixpkgs.config.cudaSupport = true;

  # ============================================================================
  # BLUETOOTH SUPPORT
  # ============================================================================

  # Enable Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # ============================================================================
  # NIX CONFIGURATION - Experimental features, build optimization, and caching
  # ============================================================================
  nix = {
    settings = {
      # Enable experimental Nix features
      experimental-features = ["nix-command" "flakes"];

      # Phase 1: Nix build optimization for Ryzen 5950X
      max-jobs = 8; # Parallel derivations (use ~1/2 of threads)
      cores = 16; # Cores per derivation (use ~1/2 of cores)

       # 8-tier binary caching + CUDA cache for maximum redundancy and performance
       substituters = [
         "https://cache.nixos.org"
         "https://nix-community.cachix.org"
         "https://ezkea.cachix.org"
         "https://nixpkgs-wayland.cachix.org"
         "https://nix-gaming.cachix.org"
         "https://cache.nixos-cuda.org"  # CUDA binary cache (fastest for GPU packages)
         "https://cache.iog.io"          # Input Output Global (reliable)
       ];
       trusted-public-keys = [
         "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
         "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
         "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
         "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
         "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
         "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
         "cache.iog.io-1:3qt3qqlXhyl2HGK8UE1Eh12NEmoyK8mx81uDWDAKPn4="
       ];
    };
  };

  # ============================================================================
  # SYSTEMD SLICES - Workload isolation for builds
  # ============================================================================
  systemd = {
    # Systemd slices for workload prioritization
    slices = {
      # Systemd slice for nix builds to prevent user responsiveness degradation
      "nix.slice" = {
        description = "Nix build processes slice";
        sliceConfig = {
          MemoryHigh = "80%"; # Limit memory usage
          CPUQuota = "80%"; # Limit CPU usage
        };
      };
    };

    # Nix daemon service configuration
    services.nix-daemon.serviceConfig.Slice = "nix.slice";
  };

  imports = [
    # Custom modules
    ./modules/base.nix
    ./modules/hardware.nix
    ./modules/desktop.nix
    ./modules/users.nix
    ./modules/nix-config.nix
    ./modules/system-packages.nix
    ./modules/environment.nix
    ./modules/ssh.nix
    ./modules/systemd-slices.nix
    ./modules/networking-shared.nix
    ./modules/mining.nix
    ./modules/storage.nix
    # ./modules/gaming.nix # This is now imported per-host

    # MCP server integration - TEMPORARILY DISABLED
    # ./modules/mcp-server.nix

    # Hardware configuration handled per-node
  ];

  # ============================================================================
  # BOOT CONFIGURATION - Bootloader and root file system
  # ============================================================================
  boot = {
    # Bootloader configuration
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Phase 1: Foundation - High-performance kernel parameters
    kernelParams = [
      # Wine gaming performance
      "fsync.enable=1"

      # NVIDIA optimizations
      "nvidia-drm.modeset=1"
      "threadirqs"

      # Ryzen 5950X optimizations
      "amd_pstate=active"
      "mitigations=off"
      "transparent_hugepage=madvise"
      "numa_balancing=disable"
      "nowatchdog"

      # PCIe and I/O optimizations
      "pcie_aspm=off"
      "elevator=none"

      # High-priority gaming optimizations
      "isolcpus=managed_applications" # CPU isolation for gaming
      "nohz_full=1-15" # Disable tick on application cores
      "rcu_nocbs=1-15" # RCU offload for low latency
    ];
  };

  # ============================================================================
  # NETWORKING CONFIGURATION
  # ============================================================================

  # Phase 1: CPU governor for gaming performance
  powerManagement.cpuFreqGovernor = "performance";

  # Phase 1: Memory management optimizations
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  # Phase 1: OOM daemon for memory pressure management
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableSystemSlice = true;
  };

  # ============================================================================
  # TIMEZONE AND LOCALE
  # ============================================================================

  time.timeZone = "America/Winnipeg";
  i18n.defaultLocale = "en_CA.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_CA.UTF-8";
    LC_IDENTIFICATION = "en_CA.UTF-8";
    LC_MEASUREMENT = "en_CA.UTF-8";
    LC_MONETARY = "en_CA.UTF-8";
    LC_NAME = "en_CA.UTF-8";
    LC_NUMERIC = "en_CA.UTF-8";
    LC_PAPER = "en_CA.UTF-8";
    LC_TELEPHONE = "en_CA.UTF-8";
    LC_TIME = "en_CA.UTF-8";
  };

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================
  services = {
    # X11/WAYLAND DESKTOP ENVIRONMENT
    xserver.enable = true;
    displayManager = {
      sddm.enable = true;
      autoLogin = {
        enable = true;
        user = "j_kro";
      };
    };
    desktopManager.plasma6.enable = true;

    # ============================================================================
    # SOUND CONFIGURATION
    # ============================================================================
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    # ============================================================================
    # PRINTER SUPPORT
    # ============================================================================
    printing.enable = true;
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # SSH configured in modules/ssh.nix

    # ============================================================================
    # NVIDIA DRIVERS AND HARDWARE SUPPORT
    # ============================================================================
    xserver.videoDrivers = ["nvidia"];

    # ============================================================================
    # SYSTEM SERVICES
    # ============================================================================
    mysql = {
      enable = true;
      package = pkgs.mariadb;
    };
    redis.servers."".enable = true;
    postgresql.enable = true;

    # ============================================================================
    # FLATPAK (DISABLED)
    # ============================================================================
    flatpak.enable = true;
  };

  # ============================================================================
  # SYSTEMD SERVICES - Shader caching and other custom services
  # ============================================================================
  systemd.services = {
    # NVIDIA shader cache service with proper dependencies
    nvidia-shader-cache-manager = {
      description = "NVIDIA Shader Cache Manager";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = ''
          #!/bin/bash
          # Create shader cache directory
          mkdir -p /var/cache/nvidia/shader
          # Shader pre-caching disabled - glxinfo not available in current nixpkgs
          echo "Shader cache directory created" > /var/cache/nvidia/shader/init.log
        '';
        RemainAfterExit = "yes";
      };
      wantedBy = ["graphical-session.target"];
    };
  };

  # ============================================================================
  # HARDWARE CONFIGURATION
  # ============================================================================
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # 32-bit support for Steam/VR
  };

  # ============================================================================
  # VIRTUALIZATION SUPPORT
  # ============================================================================
  virtualisation.libvirtd.enable = true;

  # ============================================================================
  # PROGRAMS CONFIGURATION
  # ============================================================================
  programs = {
    # ============================================================================
    # DYNAMIC LINKER SUPPORT - nix-ld for mining binaries and browsers
    # ============================================================================
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        # List by default
        zlib
        zstd
        stdenv.cc.cc
        curl
        openssl
        attr
        libssh
        bzip2
        libxml2
        acl
        libsodium
        util-linux
        xz
        systemd

        # Browser-specific libraries for Chrome DevTools & Playwright MCP
        xorg.libXcomposite
        xorg.libXtst
        xorg.libXrandr
        xorg.libXext
        xorg.libX11
        xorg.libXfixes
        libGL
        libva
        pipewire
        xorg.libxcb
        xorg.libXdamage
        xorg.libxshmfence
        xorg.libXxf86vm
        libelf
        glib
        gtk3
        pango
        cairo
        atk
        gdk-pixbuf
        fontconfig
        freetype
        dbus
        alsa-lib
        expat
        nspr
        nss
        xorg.libXcursor
        xorg.libXft
        xorg.libXi
        xorg.libXrender
        xorg.libXtst
      ];
    };

    # ============================================================================
    # SHELL CONFIGURATION
    # ============================================================================
    fish = {
      enable = true;
      useBabelfish = true; # Translate shell aliases
      vendor = {
        completions.enable = true;
        config.enable = true;
        functions.enable = true;
      };
    };
  };

  # ============================================================================
  # PHASE 1: SYSCTL OPTIMIZATIONS FOR GAMING
  # ============================================================================

  boot.kernel.sysctl = {
    # Network optimizations for gaming
    "net.core.rmem_max" = 2500000;
    "net.core.wmem_max" = 2500000;

    # Memory management
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;

    # CPU scheduler optimizations
    "kernel.sched_min_granularity_ns" = 10000000;
    "kernel.sched_wakeup_granularity_ns" = 15000000;
    "kernel.sched_migration_cost_ns" = 500000;

    # High-priority gaming sysctl optimizations
    "kernel.sched_autogroup_enabled" = 0; # Disable autogroups for lower latency
    "kernel.sched_child_runs_first" = 0; # Allow parent to run first
    "kernel.sched_ttwu_protect" = 1; # Protect wakeups
    "kernel.sched_min_runtime" = 5000000; # Minimum runtime per slice
    "vm.dirty_ratio" = 5; # Reduce dirty page ratio
    "vm.dirty_background_ratio" = 2; # Reduce dirty background ratio
    "vm.dirty_expire_centisecs" = 100; # Faster dirty page expiration
    "vm.dirty_writeback_centisecs" = 50; # Faster writeback
    "kernel.timer_migration" = 1; # Allow timer migration
    "kernel.perf_event_paranoid" = -1; # Allow perf monitoring
  };

  # ============================================================================
  # MCP SERVER INTEGRATION - TEMPORARILY DISABLED
  # ============================================================================

  # ============================================================================
  # SYSTEM ENVIRONMENT VARIABLES
  # ============================================================================

  environment.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "zen";
    NIXOS_OZONE_WL = "1";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
    WLR_EGL_NO_MODIFIERS = "1";
    STEAM_RUNTIME = "1";

    # Vulkan GPU detection for applications like LM Studio
    VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";

     # CUDA environment for AI/ML applications (handled in environment.nix)
  };

  system.stateVersion = "26.05";
}
