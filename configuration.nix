{
  pkgs,
  inputs ? null,
  ...
}: let
  # Get gamemode package for polkit rules
  gamemodePkg = pkgs.gamemode;
in {
  # ============================================================================
  # KERNEL CONFIGURATION - Force ZEN kernel for gaming and mining performance
  # ============================================================================
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # Blacklist nouveau and NovaCore drivers to ensure proper NVIDIA driver loads
  boot.blacklistedKernelModules = ["nouveau" "nova" "nova_core"];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.cudaSupport = true;

  # ============================================================================
  # NIX CONFIGURATION - Experimental features only
  # Build optimization settings are in modules/nix-config.nix
  # ============================================================================
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      # max-jobs and cores are configured in modules/nix-config.nix
    };
  };

  # ============================================================================
  # SYSTEMD SLICES - Workload isolation for builds (defined in modules/systemd-slices.nix)
  # ============================================================================
  # Note: Full slice configuration (nix.slice, gaming.slice, mining.slice) is in modules/systemd-slices.nix

  # ============================================================================
  # KERNEL MODULES
  # ============================================================================
  # Note: NVIDIA modules are loaded automatically when services.xserver.videoDrivers = ["nvidia"]
  # No need to manually specify them here

  # ============================================================================
  # POLKIT RULES - Fix gamemode permission issues
  # Using pkgs.gamemode path instead of hardcoded store path
  # ============================================================================
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.policykit.exec" &&
          (action.lookup("program") == "${gamemodePkg}/libexec/cpugovctl" ||
           action.lookup("program") == "${gamemodePkg}/libexec/procsysctl")) {
        return polkit.Result.YES;
      }
    });
  '';

  imports = [
    ./modules
    ./modules/flatpak.nix
    # Graceful distributed builds: conservative (4 jobs) when alone, aggressive (21 jobs) with builders
    ./modules/distributed-builds-graceful.nix
    ./secrets/agenix-secrets.nix
  ];

  # XDG Desktop Portal for KDE integration (with GTK fallback for Flatpak/Steam)
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      kdePackages.xdg-desktop-portal-kde # Primary KDE portal
      xdg-desktop-portal-gtk # Fallback for GTK/Flatpak apps
    ];
    config = {
      common = {
        default = ["kde" "gtk"];
      };
    };
  };

  # ============================================================================
  # BOOT CONFIGURATION - Bootloader and root file system
  # ============================================================================
  boot = {
    loader = {
      systemd-boot.enable = true;
      systemd-boot.configurationLimit = 10;  # Keep only last 10 boot entries
      efi.canTouchEfiVariables = true;
    };

    # Limit system generations to prevent EFI partition filling up
    loader.generationsDir.copyKernels = false;  # Don't copy kernels to /boot for each generation

    # Minimal kernel parameters
    kernelParams = [
      # Steam/Wine gaming
      "fsync.enable=1"

      # CPU optimizations
      "amd_pstate=active"
      "mitigations=off"
      "transparent_hugepage=madvise"
      "numa_balancing=disable"
      "nowatchdog"
      "pcie_aspm=off"

      # USB: Reduce timeout for faster boot when devices fail to enumerate
      "usbcore.use_both_schemes=y"
      "usbcore.autosuspend=-1"

      # Disable simple-framebuffer to prevent monitor conflicts with NVIDIA
      "simpledrm.disable=1"
    ];

    # System tuning
    kernel.sysctl = {
      "net.core.rmem_max" = 2500000;
      "net.core.wmem_max" = 2500000;
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
    memoryPercent = 50; # Use 50% of RAM for zram
    priority = 100; # Higher priority than disk swap
  };

  # ============================================================================
  # EARLYOOM - Lenient OOM handling to prevent session killing
  # ============================================================================
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 2; # Only kill when < 2% memory free (very lenient)
    freeSwapThreshold = 5; # Only kill when < 5% swap free
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
