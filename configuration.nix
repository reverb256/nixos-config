{pkgs, ...}: let
  # Get gamemode package for polkit rules
  gamemodePkg = pkgs.gamemode;
  # System administrator username
  sysadminUser = "j_kro";
in {
  # ============================================================================
  # USERS AND GROUPS - Configure users and groups
  # ============================================================================
  # Security: j_kro removed from docker group to prevent container escape
  # Use 'sudo docker' for container operations (requires password)
  users.users.${sysadminUser}.extraGroups = ["podman" "plugdev"]; # Removed "docker" for security, added plugdev for peripheral access

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
           action.lookup("program") == "${gamemodePkg}/libexec/procsysctl" ||
            action.lookup("program") == "${gamemodePkg}/libexec/gpuclockctl")) {  // Added gpuclockctl
        return polkit.Result.YES;
      }
    });
  '';

  imports = [
    ./modules
    ./modules/rgb.nix
    ./modules/lobster-user.nix
    # NOTE: Using nix-flatpak declarative module instead of custom flatpak.nix
    # ./modules/flatpak.nix
    # Graceful distributed builds: conservative (4 jobs) when alone, aggressive (21 jobs) with builders
    ./modules/distributed-builds-graceful.nix
    # Secrets must be imported AFTER agenix module
    ./secrets/agenix-secrets.nix
    # OpenClaw service module
    ./modules/services/openclaw
  ];

  # OpenClaw AI Gateway Service
  services.openclaw = {
    enable = true;
    port = 18789;
    autoStart = true;
  };

  # ============================================================================
  # PERIPHERAL DEVICE SUPPORT - Razer and Corsair devices
  # Using built-in hardware.openrazer module for proper daemon setup
  # ============================================================================
  hardware.openrazer.enable = true;

  hardware.peripherals = {
    enable = true;
    corsair = {
      enable = true;
      ckbNext = true;
    };
  };

  # RGB Lighting Control
  # MSI X570 Tomahawk + RTX 3090 + Corsair devices + G.Skill Trident Z RGB
  hardware.rgb = {
    enable = true;
    openrgb = {
      enable = true;
      withPlugins = true;
    };
    corsair = {
      enable = true; # ckb-next handles keyboard + Lighting Node Pro
    };
  };

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
      kde = {
        default = ["kde" "gtk"];
        "org.freedesktop.impl.portal.FileChooser" = ["kde" "gtk"];
        "org.freedesktop.impl.portal.ScreenCast" = ["kde"];
        "org.freedesktop.impl.portal.Screenshot" = ["kde"];
        "org.freedesktop.impl.portal.RemoteDesktop" = ["kde"];
        "org.freedesktop.impl.portal.Settings" = ["kde" "gtk"];
        "org.freedesktop.impl.portal.Notification" = ["kde"];
        "org.freedesktop.impl.portal.WindowManagement" = ["kde"];
      };
    };
    xdgOpenUsePortal = true;
  };

  # Declarative Flatpak configuration using nix-flatpak module
  services.flatpak = {
    enable = true;
    polkit.enable = true;
    polkit.allowSystemOperations = true;
    remotes = [
      {
        name = "flathub";
        location = "https://flathub.org/repo/flathub.flatpakrepo";
      }
      {
        name = "flathub-beta";
        location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
      }
    ];
    packages = [
      # Keep existing system-wide Flatpak apps
      # Note: nix-flatpak uses just the app ID, not "remote:app-id" format
      "com.spotify.Client"
      "io.github.kolunmi.Bazaar"
      "org.gnome.Calculator"
      "org.gnome.Fractal"
      "org.telegram.desktop"
      "org.kde.audiotube"
    ];
  };

  # Podman configuration for container management
  virtualisation.podman = {
    enable = true;
    # Disable Docker socket to avoid conflict (enable only if needed for Docker compatibility)
    dockerSocket.enable = false;
    defaultNetwork.settings.dnsname.enable = true; # Enable DNS for containers
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Note: Docker is not explicitly enabled, avoiding conflict with podman's Docker socket
  # virtualisation.docker.enable = false;  # Only enable if podman dockerSocket causes issues

  # OCI Containers configuration for container management
  virtualisation.oci-containers = {
    backend = "podman"; # Use podman as backend

    # Note: Specific containers managed via individual services when needed
    # containers = {
    #   # Example containers definitions would go here if needed
    # };
  };

  # ============================================================================
  # BOOT CONFIGURATION - Bootloader and root file system
  # ============================================================================
  boot = {
    loader = {
      systemd-boot.enable = true;
      systemd-boot.configurationLimit = 10; # Keep only last 10 boot entries
      efi.canTouchEfiVariables = true;
    };

    # Limit system generations to prevent EFI partition filling up
    loader.generationsDir.copyKernels = false; # Don't copy kernels to /boot for each generation

    # Minimal kernel parameters
    kernelParams = [
      # Steam/Wine gaming
      "fsync.enable=1"

      # CPU optimizations
      "amd_pstate=active"
      # "mitigations=off"  # REMOVED for security - CPU vulnerabilities exposed
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
  # MOSH - Mobile Shell for roaming connections
  # ============================================================================
  programs.mosh.enable = true;

  # ============================================================================
  # FIREWALL - Mosh uses UDP ports 60000-61000
  # ============================================================================
  networking.firewall.allowedUDPPorts = [60000 60001 60002 60003 60004];

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

  # OpenClaw Storage Management Control Plane (runs with lobster user)
  # Temporarily disabled until minio-cache-credentials are properly set up
  # services.openclaw-storage = {
  #   enable = true;
  #   port = 18800;
  #   aistorEndpoint = "http://10.1.1.120:9000"; # nexus (AIStor)
  #   aistorCredentialsFile = "/run/agenix/minio-cache-credentials"; # Requires secret creation
  #   # Use default buckets from module
  # };

  # OpenClaw automated backups to cloud storage - Temporarily disabled pending secret setup
  # services.openclaw-backups = {
  #   enable = true;
  # };

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
