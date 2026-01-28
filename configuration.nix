{pkgs, ...}: {
  # ============================================================================
  # KERNEL CONFIGURATION - Force ZEN kernel for gaming and mining performance
  # ============================================================================
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # NVIDIA configuration for RTX 3090 (use proprietary drivers with ZEN kernel)
  hardware.nvidia = {
    package = pkgs.linuxPackages_zen.nvidiaPackages.beta;
    modesetting.enable = true;
    open = false;
    # Enhanced DRM support for Wayland
    nvidiaSettings = true;
    powerManagement.enable = true;
  };

  # Enable proper OpenCL ICD registration for mining
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      nvidia-vaapi-driver  # Provides proper NVIDIA OpenCL ICD
    ];
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

      # Moved caching configuration to nix-config.nix to prevent duplication
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

  # ============================================================================
  # KERNEL MODULES FOR NVIDIA HARDWARE ACCELERATION
  # ============================================================================
  boot.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];

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

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Modular configurations
    ./modules
    # NVIDIA sandbox configuration
    ./modules/nvidia-sandbox.nix
    # Flatpak support
    ./modules/flatpak.nix
  ];

  # XDG Desktop Portal for KDE integration
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
  };

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

      # NVIDIA Wayland optimizations
      "nvidia-drm.modeset=1"
      "nvidia_drm.fbdev=0" # Disable fbdev for better Wayland support
      "nvidia.NVreg_EnableResizableBar=1"
      "nvidia.NVreg_UsePageAttributeTable=1"
      "nvidia-uvm/uvm_disable_huge_pages=1"
      "threadirqs"

      # Enhanced NVIDIA RTX 3090 optimizations (Zen kernel compatible)
      "nvidia.NVreg_RegistryDwords=PerfLevelSrc=0x2222"
      "nvidia.NVreg_UsePageAttributeTable=1" # Better memory management
      "nvidia.NVreg_EnableResizableBar=1" # Resizable BAR for RTX 3090
      "nvidia-uvm/uvm_disable_huge_pages=1" # Fix Wayland compatibility
      # Additional NVIDIA parameters for Wayland stability
      "nvidia.NVreg_RegistryDwords=PerfLevelSrc=0x2222;NVreg_UsePageAttributeTable=1;EnableResizableBar=1"

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
      # "isolcpus=managed_applications" # CPU isolation for gaming
      # "nohz_full=1-15" # Disable tick on application cores
      # "rcu_nocbs=1-15" # RCU offload for low latency
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
  # Set state version to avoid warnings
  system.stateVersion = "26.05";

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
  # AUTO-UPGRADE CONFIGURATION
  # ============================================================================
  system.autoUpgrade = {
    enable = true;
    # Weekly updates (default is daily)
    dates = "weekly"; # Can be set to "daily", "weekly", or a cron-like schedule
    # Use the same channel as specified in your flake
    channel = "https://nixos.org/channels/nixos-unstable";
  };

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================
  services = {
    # X11/WAYLAND DESKTOP ENVIRONMENT
    displayManager = {
      sddm.enable = true;
      autoLogin = {
        enable = true;
        user = "j_kro";
      };
      # Force Wayland session for hardware acceleration
      defaultSession = "plasma";
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
  };
}
