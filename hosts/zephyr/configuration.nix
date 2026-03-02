# Zephyr Host Configuration
# RTX 3090, Quest Pro, 4K HDR TV
{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Hardware modules (NVIDIA GPU)
    ../../modules/hardware/nvidia-common.nix
    #../../modules/hardware/nvidia-wayland.nix  # DISABLED: Causes KWin EGL crashes with multi-GPU

    # Modules (all other modules)
    ../../modules/default.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "zephyr";
  networking.networkmanager.enable = true;

  # Timezone and locale
  time.timeZone = "America/Winnipeg";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # Zephyr-specific kernel params for gaming
  boot.kernelParams = [
    "split_lock_detect=off"
    "threadirqs"
    "preempt=full"
    "processor.max_cstate=1"
    "intel_idle.max_cstate=1"
    "iommu=pt"
  ];

  # ============================================================================
  # GAMING + VR (Full support - RTX 3090)
  # ============================================================================
  services.gaming = {
    enable = true;
    vr.enable = true; # WiVRn for Quest Pro
    hdr.enable = true; # HDR for 4K HDR TV
  };

  # ============================================================================
  # SCOPEBUDDY - Gamescope wrapper
  # ============================================================================
  programs.scopebuddy = {
    enable = true;
    autoDetect = {
      resolution = true;
      hdr = true;
      vrr = true;
    };
  };

  # ============================================================================
  # ANIME GAME LAUNCHERS
  # ============================================================================
  programs.anime-game-launcher.enable = true;
  programs.sleepy-launcher.enable = true;
  programs.honkers-railway-launcher.enable = true;
  programs.wavey-launcher.enable = true;

  # ============================================================================
  # AI SERVICES - LM Studio & Stability Matrix
  # ============================================================================
  programs.lm-studio.enable = true;
  programs.stability-matrix.enable = true;

  # ============================================================================
  # MINING - GPU Mining (RTX 3090)
  # ============================================================================
  services.mining.enable = true;

  # NVIDIA GPU configuration for RTX 3090 only
  services.mining.lolminer.nvidia = {
    enable = true;
    devices = "1";  # RTX 3090 only (GPU 1) - 3060 Ti disabled for gaming
    powerLimit = 250;  # Power limit for RTX 3090 (250W recommended for efficiency)
    apiPort = 4068;
  };

  # ============================================================================
  # PER-GPU POWER LIMITS
  # ============================================================================
  # RTX 3060 Ti (GPU 0): 130W for efficient mining
  systemd.services."gpu-0-power-limit" = {
    description = "Set RTX 3060 Ti power limit to 130W";
    wantedBy = ["multi-user.target"];
    before = ["lolminer-nvidia.service"];
    requiredBy = ["lolminer-nvidia.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/run/current-system/sw/bin/nvidia-smi -i 0 -pl 130";
    };
  };

  # RTX 3090 (GPU 1): 250W for balanced performance/efficiency
  systemd.services."gpu-1-power-limit" = {
    description = "Set RTX 3090 power limit to 250W";
    wantedBy = ["multi-user.target"];
    before = ["lolminer-nvidia.service"];
    requiredBy = ["lolminer-nvidia.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/run/current-system/sw/bin/nvidia-smi -i 1 -pl 250";
    };
  };

  # Mining plasmoid for KDE Plasma
  #programs.mining-plasmoid.enable = true;  # TODO: Requires plasmoids/mining-monitor

  # ============================================================================
  # MONITORING - Full monitoring stack
  # ============================================================================
  # System metrics
  services.monitoring.node-exporter.enable = true;

  # GPU metrics exporter (NVIDIA RTX 3090)
  services.gpu-exporters.enable = true;

  # Mining metrics exporter (XMRig + lolMiner)
  services.mining-exporter.enable = true;

  # Prometheus server - central metrics collection
  services.monitoring.prometheus.enable = true;
  services.monitoring.prometheus.retentionDays = 30;
  services.monitoring.prometheus.scrapeInterval = "15s";

  # Grafana dashboards
  services.monitoring.grafana.enable = true;

  # ============================================================================
  # TAILSCALE
  # ============================================================================
  services.tailscale.enable = true;

  # ============================================================================
  # ADDITIONAL PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # Shell & CLI
    fish
    starship
    zoxide
    fzf
    eza
    btop

    # Version control
    tmux
    mosh
    git

    # Networking
    tailscale
    networkmanager
    dbus-broker

    # Development
    nodejs
    gh
    inputs.claude-native.packages.x86_64-linux.claude

    # AI & ML
    llama-cpp
    whisper-cpp

    # Mining (manual only, no auto-start)
    xmrig
    lolminer

    # Desktop
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
  ];

  # ============================================================================
  # HOME MANAGER - Zen Browser with Extensions
  # ============================================================================
  home-manager.users.j_kro = { pkgs, lib, ... }: {
    imports = [
      inputs.zen-browser.homeModules.twilight
      inputs.nixcord.homeModules.nixcord
    ];
    home.stateVersion = "26.05";
    programs.zen-browser = {
      enable = true;
      suppressXdgMigrationWarning = true;
      policies = {
        DisableAppUpdate = true;
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DisableFeedbackCommands = true;
        DisablePocket = true;
        NoDefaultBookmarks = true;
        OfferToSaveLogins = false;
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };

        # Dark Reader extension
        ExtensionSettings = {
          "addon@darkreader.org" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
          };
        };
      };
      profiles.default = {
        extensions.packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
          ublock-origin
          bitwarden
          privacy-badger
          decentraleyes
          noscript
          clearurls
          cookie-autodelete
          privacy-pass
        ];
      };
    };

    # ============================================================================
    # NIXCORD - Declarative Discord/Vesktop Configuration
    # ============================================================================
    programs.nixcord = {
      enable = true;
      discord.enable = false;
      vesktop.enable = true;

      # Plugins
      vesktopConfig = {
        plugins = {
          XSOverlay = {
            enable = true;
            dmNotifications = true;
            groupDmNotifications = true;
            serverNotifications = true;
            callNotifications = true;
            channelPingColor = "#8a2be2";
            pingColor = "#7289da";
            timeout = 3;
            volume = 0.2;
            opacity = 1.0;
          };
          fakeNitro = {
            enable = true;
            enableEmojiBypass = true;
            enableStickerBypass = true;
            enableStreamBypass = true;
            emojiSize = 48.0;
          };
          USRBG = {
            enable = true;
            nitroFirst = true;
            voiceBackground = true;
          };
          ReviewDB = {
            enable = true;
          };
        };
      };
    };

    # Autostart Vesktop on login
    systemd.user.services.vesktop-autostart = {
      Unit = {
        Description = "Vesktop autostart";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.vesktop}/bin/vesktop --enable-features=UseOzonePlatform --ozone-platform-hint=auto";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };

  # ============================================================================
  # FIREWALL
  # ============================================================================
  networking.firewall = {
    allowedTCPPorts = [
      9757  # WiVRn
      18789
      18790
      19898
    ];
    allowedUDPPorts = [
      9757  # WiVRn
      9758
      9759
      27031
      27036
      5353  # mDNS
      9947  # WiVRn
    ];
    interfaces."tailscale0".allowedTCPPorts = [
      18789
      18790
    ];
  };

  # ============================================================================
  # SYSTEM STATE
  # ============================================================================
  system.stateVersion = "26.05";
}
