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

    # ============================================================================
    # POLKIT RULES - Fix gamemode permission issues
    # ============================================================================
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.policykit.exec" && 
            (action.lookup("program") == "/nix/store/8qf4gd46bf9nq7iiq27kjiac5wya3gd5-gamemode-1.8.2/libexec/cpugovctl" ||
             action.lookup("program") == "/nix/store/8qf4gd46bf9nq7iiq27kjiac5wya3gd5-gamemode-1.8.2/libexec/procsysctl")) {
          return polkit.Result.YES;
        }
      });
    '';
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
    ./modules/gaming.nix # This is now imported per-host

    # Nix cache server
    ./modules/nix-cache-server.nix

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
        # "elevator=none" # Deprecated - use sysfs instead

        # High-priority gaming optimizations
        "isolcpus=managed_applications" # CPU isolation for gaming
        "nohz_full=1-15" # Disable tick on application cores
        "rcu_nocbs=1-15" # RCU offload for low latency
      ];

      # ============================================================================
      # SYSTEM TUNING - Optimizations for Ryzen 5950X and RTX 3090
      # ============================================================================
      kernel.sysctl = {
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
        "kernel.perf_event_mlock_kb" = 516; # RTX 3090 compute optimization
        
        # NEW: VR/Streaming memory optimizations
        "vm.max_map_count" = 262144; # For VR applications
        "kernel.shmmax" = 134217728; # Shared memory for VR
        "kernel.shmall" = 32768; # Page shared memory
        
        # I/O scheduler (replaces deprecated elevator=none)
        "block/queue/scheduler" = "none"; # Use none scheduler for NVMe SSDs
      };
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

    # ============================================================================
    # NVIDIA DRIVERS AND HARDWARE SUPPORT
    # ============================================================================
    xserver.videoDrivers = ["nvidia"];
  };
   system.stateVersion = "26.05";
}
