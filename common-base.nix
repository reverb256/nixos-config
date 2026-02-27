{
  lib,
  ...
}:
let
  # System administrator username
  sysadminUser = "j_kro";
  inherit (lib) mkDefault;
in
{
  # ============================================================================
  # SYSTEMD - Prevent display manager restart during rebuild
  # ============================================================================
  # This prevents Plasma 6 Wayland session termination on configuration changes
  systemd.services.display-manager.restartIfChanged = false;
  systemd.services.sddm.restartIfChanged = false;

  # Blacklist nouveau and NovaCore drivers to ensure proper NVIDIA driver loads
  boot.blacklistedKernelModules = [
    "nouveau"
    "nova"
    "nova_core"
  ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.cudaSupport = true;

  # ============================================================================
  # NIX CONFIGURATION - Experimental features only
  # Build optimization settings are in modules/nix-config.nix
  # ============================================================================
  # NixOS Cluster Configuration
  nix.settings = {
    trusted-users = [ "j_kro" ];
    auto-optimise-store = true;
    # max-jobs and cores are configured in modules/nix-config.nix
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
  # Uses specific GameMode action IDs instead of generic pkexec
  # ============================================================================
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (
        (action.id == "com.feralinteractive.GameMode.governor-helper" ||
         action.id == "com.feralinteractive.GameMode.procsys-helper" ||
         action.id == "com.feralinteractive.GameMode.gpu-helper") &&
        subject.user == "${sysadminUser}"
      ) {
        return polkit.Result.YES;
      }
    });
  '';

  imports = [
    ./modules
    # Mining-aware build wrapper (pause/resume during builds)
    ./modules/mining/mining-build-wrapper.nix
    # Storage configuration modules
    ./modules/system/storage.nix
    ./modules/system/storage-btrfs.nix
    # Secrets configuration (agenix)
    ./secrets/agenix-secrets.nix
    # Stylix + Base24 hybrid theming configuration
    ./modules/desktop/stylix-base24.nix
  ];

  # ============================================================================
  # PERIPHERAL DEVICE SUPPORT - Razer and Corsair devices
  # Using built-in hardware.openrazer module for proper daemon setup
  # ============================================================================
  hardware.openrazer.enable = true;

  # RGB Lighting Control - Supports Corsair, Razer, Gigabyte/Aorus, MSI, EVGA
  hardware.rgb = {
    enable = true;
    openrgb = {
      enable = true;
      withPlugins = true;
    };
    corsair = {
      enable = true;
      ckbNext = true;
    };
  };

  # RGB Lighting Control
  # MSI X570 Tomahawk + RTX 3090 + Corsair devices + G.Skill Trident Z RGB
  # RGB devices managed via existing modules (plasma6.nix, system-packages.nix)

  # NOTE: Stylix theming is configured in flake.nix to ensure proper module order

  # Note: XDG Portal configuration is now split:
  #   - Plasma: modules/desktop/plasma6.nix
  #   - Hyprland: modules/desktop/hyprland.nix
  #   - Niri: modules/desktop/niri.nix

  # Modern D-Bus implementation (better performance, security, and features)
  # services.dbus.implementation = "broker";  # Commented out - causes critical switch inhibitor

  # ============================================================================
  # FLATPAK - Declarative configuration with Flathub integration
  # ============================================================================
  # Using nix-flatpak module for declarative remotes and packages
  # Activation scripts handle overrides for Wayland, theming, and gaming
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

  # Flatpak overrides - Wayland, theming, and Steam integration
  # These activation scripts run after flatpak-remotes are configured
  system.activationScripts.flatpak-overrides = lib.stringAfter [ "usrbinenv" ] ''
        # Create global overrides directory
        mkdir -p /var/lib/flatpak/overrides

        # Global override - Comprehensive socket and filesystem access
        cat > /var/lib/flatpak/overrides/global << 'EOF'
    [Context]
    # Socket access - comprehensive for all app types
    sockets=wayland;x11;pulseaudio;session-bus;system-bus;ssh-auth;pcsc;cups;gpg-agent;

    # Filesystem access - common user directories
    filesystems=xdg-download;xdg-documents;xdg-pictures;xdg-music;xdg-videos;xdg-desktop;xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro;xdg-config/Kvantum:ro;xdg-config/qt5ct:ro;xdg-config/qt6ct:ro;

    # Device access - needed for GPU acceleration, controllers, etc.
    devices=dri;shm;all;

    # Shared resources
    shared=network;ipc;

    # Features
    features=bluetooth;canbus;inhibit;multiarch;devel;

    [Environment]
    # Theming
    XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons
    GTK_THEME=Breeze
    QT_QPA_PLATFORMTHEME=kde
    QT_STYLE_OVERRIDE=Breeze

    # Wayland by default, but allow X11 fallback
    SDL_VIDEODRIVER=wayland
    QT_QPA_PLATFORM=wayland
    GDK_BACKEND=wayland

    # Fix for NVIDIA + Flatpak
    __GLX_VENDOR_LIBRARY_NAME=nvidia
    EOF

        # Steam override - Additional permissions for gaming
        cat > /var/lib/flatpak/overrides/com.valvesoftware.Steam << 'EOF'
    [Context]
    sockets=wayland;x11;pulseaudio;system-talk-bus;session-talk-bus;
    filesystems=xdg-download;xdg-documents;xdg-pictures;xdg-music;xdg-videos;~/.local/share/Steam:create;~/.steam:create;/run/media:rw;/mnt:rw;
    devices=all;
    shared=network;

    [Environment]
    XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons
    GTK_THEME=Breeze
    QT_QPA_PLATFORMTHEME=kde
    SDL_VIDEODRIVER=wayland
    EOF

        # Steam Proton compatibility tool override
        cat > /var/lib/flatpak/overrides/com.valvesoftware.Steam.CompatibilityTool.Proton << 'EOF'
    [Context]
    filesystems=~/.local/share/Steam:rw;~/.steam:rw;
    EOF
  '';

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

  # OCI Containers configuration for container management
  virtualisation.oci-containers = {
    backend = "podman"; # Use podman as backend

    # Note: Specific containers managed via individual services when needed
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

      # NVMe optimization for gaming - faster error detection
      "nvme_core.io_timeout=15"
    ];

    # System tuning
    kernel.sysctl = {
      "net.core.rmem_max" = 2500000;
      "net.core.wmem_max" = 2500000;
      "vm.vfs_cache_pressure" = 50;
      "kernel.sched_autogroup_enabled" = 0;
      "kernel.perf_event_paranoid" = -1;
      "kernel.shmmax" = 134217728;
      # Swap optimization for gaming - less aggressive swapping, more responsive
      "vm.swappiness" = 60; # Down from default 60 (or your previous 80) - less swap pressure
      "vm.page-cluster" = 0; # Down from 3 - single page reads, more responsive swap
      "vm.overcommit_ratio" = 90; # Allow overcommit for gaming/malloc-heavy apps
    };
  };

  # I/O Scheduler for NVMe SSDs - optimized for swap and gaming
  # Note: Scheduler is per-device, not per-partition, so use mq-deadline for all NVMe
  services.udev.extraRules = ''
    # NVMe devices - use mq-deadline for gaming/swap performance
    ACTION=="add|change", KERNEL=="nvme0n1", ATTR{queue/scheduler}="mq-deadline"
    ACTION=="add|change", KERNEL=="nvme1n1", ATTR{queue/scheduler}="mq-deadline"

    # Disable writeback throttling for gaming (wbt_lat_usec=0)
    ACTION=="add|change", KERNEL=="nvme0n1", ATTR{queue/wbt_lat_usec}="0"
    ACTION=="add|change", KERNEL=="nvme1n1", ATTR{queue/wbt_lat_usec}="0"

    # SATA SSDs - use mq-deadline
    ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
  '';

  # ============================================================================
  # POWER MANAGEMENT
  # Using mkDefault to allow per-host override (e.g., "schedutil" for efficiency)
  # ============================================================================
  powerManagement.cpuFreqGovernor = mkDefault "performance";

  # ============================================================================
  # MOSH - Mobile Shell for roaming connections
  # ============================================================================
  programs.mosh.enable = true;

  # ============================================================================
  # ANIME GAME LAUNCHERS (ezKEa/aagl-gtk-on-nix)
  # ============================================================================
  programs.anime-game-launcher.enable = true;
  programs.anime-games-launcher.enable = true;
  programs.honkers-railway-launcher.enable = true;
  programs.honkers-launcher.enable = true;
  programs.wavey-launcher.enable = true;
  programs.sleepy-launcher.enable = true;

  # ============================================================================
  # FIREWALL - Mosh uses UDP ports 60000-61000
  # ============================================================================
  networking.firewall.allowedUDPPorts = [
    60000
    60001
    60002
    60003
    60004
  ];

  # ============================================================================
  # ZRAM - DISABLED - Use disk swap only
  # ============================================================================
  zramSwap = {
    enable = false;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  # ============================================================================
  # EARLYOOM - Lenient OOM handling to prevent session killing
  # ============================================================================
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 2; # Only kill when <2% memory free (very lenient)
    freeSwapThreshold = 5; # Only kill when <5% swap free
  };

  # ============================================================================
  # TIMEZONE AND LOCALE
  # Using mkDefault to allow per-host overrides if needed
  # ============================================================================
  time.timeZone = mkDefault "America/Winnipeg";
  i18n.defaultLocale = mkDefault "en_CA.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = mkDefault "en_CA.UTF-8";
    LC_IDENTIFICATION = mkDefault "en_CA.UTF-8";
    LC_MEASUREMENT = mkDefault "en_CA.UTF-8";
    LC_MONETARY = mkDefault "en_CA.UTF-8";
    LC_NAME = mkDefault "en_CA.UTF-8";
    LC_NUMERIC = mkDefault "en_CA.UTF-8";
    LC_PAPER = mkDefault "en_CA.UTF-8";
    LC_TELEPHONE = mkDefault "en_CA.UTF-8";
    LC_TIME = mkDefault "en_CA.UTF-8";
  };

  # ============================================================================
  # AUTO-UPGRADE CONFIGURATION
  # ============================================================================
  system.autoUpgrade = {
    enable = true;
    dates = "weekly";
    channel = "https://nixos.org/channels/nixos-unstable";
  };
}
