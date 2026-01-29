{
  pkgs,
  inputs ? null,
  ...
}: {
  # ============================================================================
  # KERNEL CONFIGURATION - Force ZEN kernel for gaming and mining performance
  # ============================================================================
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # Blacklist nouveau and NovaCore drivers to ensure proper NVIDIA driver loads
  boot.blacklistedKernelModules = ["nouveau" "nova" "nova_core"];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.cudaSupport = true;

  # ============================================================================
  # BLUETOOTH SUPPORT
  # ============================================================================
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # ============================================================================
  # NIX CONFIGURATION - Experimental features, build optimization, and caching
  # ============================================================================
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      max-jobs = 8;
      cores = 16;
    };
  };

  # ============================================================================
  # SYSTEMD SLICES - Workload isolation for builds
  # ============================================================================
  systemd = {
    slices = {
      "nix.slice" = {
        description = "Nix build processes slice";
        sliceConfig = {
          MemoryHigh = "80%";
          CPUQuota = "80%";
        };
      };
    };
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
    ./hardware-configuration.nix
    ./modules
    ./modules/nvidia-sandbox.nix
    ./modules/flatpak.nix
    ./secrets/agenix-secrets.nix
  ];

  # XDG Desktop Portal for KDE integration
  xdg.portal = {
    enable = true;
    extraPortals = [pkgs.kdePackages.xdg-desktop-portal-kde];
  };

  # ============================================================================
  # BOOT CONFIGURATION - Bootloader and root file system
  # ============================================================================
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Clean kernel parameters - consolidated from duplicate definitions
    kernelParams = [
      # Steam/Wine gaming
      "fsync.enable=1"

      # NVIDIA Wayland support
      "nvidia-drm.modeset=1"
      "nvidia_drm.fbdev=0"
      "nvidia.NVreg_RegistryDwords=PerfLevelSrc=0x2222;NVreg_UsePageAttributeTable=1;NVreg_EnableResizableBar=1"
      "nvidia-uvm/uvm_disable_huge_pages=1"
      "threadirqs"

      # CPU optimizations
      "amd_pstate=active"
      "mitigations=off"
      "transparent_hugepage=madvise"
      "numa_balancing=disable"
      "nowatchdog"
      "pcie_aspm=off"
    ];

    # System tuning
    kernel.sysctl = {
      "net.core.rmem_max" = 2500000;
      "net.core.wmem_max" = 2500000;
      "vm.swappiness" = 10;
      "vm.vfs_cache_pressure" = 50;
      "kernel.sched_autogroup_enabled" = 0;
      "kernel.perf_event_paranoid" = -1;
      "vm.max_map_count" = 262144;
      "kernel.shmmax" = 134217728;
    };
  };

  # I/O Scheduler for NVMe SSDs - use kyber for better latency
  services.udev.extraRules = ''
    # NVMe SSDs - use kyber scheduler for better latency
    ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="kyber"
    
    # SATA SSDs - use mq-deadline
    ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
  '';

  # ============================================================================
  # POWER MANAGEMENT
  # ============================================================================
  powerManagement.cpuFreqGovernor = "performance";

  # ============================================================================
  # ZRAM - Compressed RAM swap for better performance
  # ============================================================================
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;  # Use 50% of RAM for zram
    priority = 100;      # Higher priority than disk swap
  };

  # ============================================================================
  # EARLYOOM - Better OOM handling than systemd-oomd for desktop systems
  # ============================================================================
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;      # Kill when < 5% memory free
    freeSwapThreshold = 10;    # Kill when < 10% swap free
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
    dates = "weekly";
    channel = "https://nixos.org/channels/nixos-unstable";
  };

  system.stateVersion = "26.05";
}
