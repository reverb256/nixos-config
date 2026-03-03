# Zephyr Host Configuration
# RTX 3090, Quest Pro, 4K HDR TV
{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # Hardware modules (NVIDIA GPU)
    ../../modules/hardware/nvidia-common.nix
    #../../modules/hardware/nvidia-wayland.nix  # DISABLED: Causes KWin EGL crashes with multi-GPU

    # Modules (all other modules)
    ../../modules/default.nix

    # Multimedia modules
    ../../modules/multimedia/gstreamer.nix

    # Desktop modules
    ../../modules/desktop/spotify-spotx.nix
    ../../modules/desktop/spotify-spicetify.nix
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
  # AI INFERENCE SERVICE - Gateway with authentication and metrics
  # ============================================================================
  services.ai-inference = {
    enable = true;

    # Backend: LM Studio (already running)
    backend = {
      url = "http://127.0.0.1:1234";  # LM Studio default
      type = "lm-studio";
    };

    # Gateway configuration
    gateway = {
      enable = true;
      host = "127.0.0.1";  # Local only initially
      port = 8080;
      workers = 4;
    };

    # Intelligent routing
    routing = {
      enable = true;
      defaultModel = "qwen3.5-4b";
      rules = [
        {
          minTokens = 0;
          maxTokens = 4096;
          model = "qwen3.5-2b";
          priority = 10;
        }
        {
          minTokens = 4097;
          maxTokens = 32768;
          model = "qwen3.5-4b";
          priority = 20;
        }
        {
          minTokens = 32769;
          maxTokens = 999999;
          model = "qwen3.5-35b-a3b@q4_k_m";
          priority = 30;
        }
      ];
    };

    # Authentication: start with none (local)
    auth.mode = "none";

    # Monitoring: integrate with existing Prometheus
    monitoring = {
      enable = true;
      port = 9090;
    };
  };

  # ============================================================================
  # MINING - GPU Mining (RTX 3090)
  # ============================================================================
  services.mining.enable = true;

  # ============================================================================
  # MULTIMEDIA - GStreamer support for Qt/KDE applications
  # ============================================================================
  services.multimedia.gstreamer.enable = true;

  # Spotify with SpotX patch
  services.spotify-spotx.enable = true;

  # Spotify with Spicetify theming (requires SpotX)
  services.spotify-spicetify = {
    enable = true;
    theme = "Dribbblish";
    colorScheme = "nord-dark";
    extensions = [
      "adblock"
      "shuffle+"
    ];
  };

  # ============================================================================
  # FLATPAK - Flatpak support with Discover and Flathub
  # ============================================================================
  services.flatpak-kde = {
    enable = true;
    autoUpdate = true;
  };

  # NVIDIA GPU configuration for RTX 3090 only
  services.mining.lolminer.nvidia = {
    enable = true;
    devices = "1"; # RTX 3090 only (GPU 1) - 3060 Ti disabled for gaming
    powerLimit = 250; # Power limit for RTX 3090 (250W recommended for efficiency)
    apiPort = 4068;
  };

  # XMRig CPU mining
  services.mining.xmrig.enable = true;

  # ============================================================================
  # PER-GPU POWER LIMITS
  # ============================================================================
  # RTX 3060 Ti (GPU 0): 130W for efficient mining
  systemd.services."gpu-0-power-limit" = {
    description = "Set RTX 3060 Ti power limit to 130W";
    wantedBy = [ "multi-user.target" ];
    before = [ "lolminer-nvidia.service" ];
    requiredBy = [ "lolminer-nvidia.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/run/current-system/sw/bin/nvidia-smi -i 0 -pl 130";
    };
  };

  # RTX 3090 (GPU 1): 250W for balanced performance/efficiency
  systemd.services."gpu-1-power-limit" = {
    description = "Set RTX 3090 power limit to 250W";
    wantedBy = [ "multi-user.target" ];
    before = [ "lolminer-nvidia.service" ];
    requiredBy = [ "lolminer-nvidia.service" ];
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

    # Music
    spotube
  ];

  # ============================================================================
  # HOME MANAGER - Zen Browser with Extensions
  # ============================================================================
  home-manager = {
    backupFileExtension = "bak";
    users.j_kro =
      { pkgs, ... }:
      {
        imports = [
          inputs.zen-browser.homeModules.twilight
          inputs.nixcord.homeModules.nixcord
        ];
        home.stateVersion = "26.05";

        # Mask Vesktop XDG autostart file to prevent SIGILL crash
        # The XDG autostart uses the wrong Electron binary (unwrapped vs wrapped)
        # We use systemd user service instead for proper autostart
        xdg.configFile."autostart/vesktop.desktop".text = ''
          [Desktop Entry]
          Hidden=true
          X-GNOME-Autostart-enabled=false
          X-KDE-autostart-after-panel=false
        '';

        programs.zen-browser = {
          enable = true;
          suppressXdgMigrationWarning = true;

          # PWA Support - enables installing websites as native applications
          nativeMessagingHosts = [ pkgs.firefoxpwa ];

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

            # Extension Management via Policies
            # - force_installed: Cannot be disabled by user (essential security)
            # - normal_installed: User can configure per-site exceptions
            ExtensionSettings = {
              # Essential Security (force-installed)
              "uBlock0@raymondhill.net" = {
                installation_mode = "force_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
              };
              "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
                installation_mode = "force_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
              };
              "jid1-BoFifL9Vbdl2zQ@jetpack" = {
                installation_mode = "force_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/decentraleyes/latest.xpi";
              };
              "addon@darkreader.org" = {
                installation_mode = "force_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
              };

              # User-Configurable (allows per-site exceptions for sites like Outlook)
              "jid1-MnnxcxisBPnSXQ@jetpack" = {
                installation_mode = "normal_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/privacy-badger17/latest.xpi";
              };
              "{73a6fe31-595d-460b-a920-fcc0f8843232}" = {
                installation_mode = "normal_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi";
              };
              "{74145f27-f039-47ce-a470-a662b129930a}" = {
                installation_mode = "normal_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/clearurls/latest.xpi";
              };
              "CookieAutoDelete@kennydo.com" = {
                installation_mode = "normal_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/cookie-autodelete/latest.xpi";
              };
              "{48748554-4c01-49e8-94af-79662bf34d50}" = {
                installation_mode = "normal_installed";
                install_url = "https://addons.mozilla.org/firefox/downloads/latest/privacy-pass/latest.xpi";
              };
            };
          };

          profiles.default = {
            id = 0;
            name = "default";
            isDefault = true;

            # Prevent manual changes to declarative settings
            containersForce = true;
            pinsForce = true;
            spacesForce = true;

            # Custom about:config preferences
            extraConfig = ''
              // Zen-specific preferences
              user_pref("zen.theme.sidebar", "auto");
              user_pref("zen.view.compact", true);
              user_pref("zen.workspaces.vertical", true);

              // Performance optimizations
              user_pref("gfx.webrender.all", true);
              user_pref("media.ffmpeg.vaapi.enabled", true);
              user_pref("widget.dmabuf.force-enabled", true);

              // Privacy enhancements
              user_pref("privacy.resistFingerprinting", true);
              user_pref("network.http.referer.spoofSource", true);
              user_pref("privacy.trackingprotection.enabled", true);
            '';

            # Declarative Containers (Multi-Account Containers)
            containers = {
              "Dev" = {
                color = "blue";
                icon = "fingerprint";
                id = 1;
              };
              "Personal" = {
                color = "green";
                icon = "briefcase";
                id = 2;
              };
              "Finance" = {
                color = "orange";
                icon = "dollar";
                id = 3;
              };
              "Gaming" = {
                color = "purple";
                icon = "circle";
                id = 4;
              };
              "AI" = {
                color = "turquoise";
                icon = "pet";
                id = 5;
              };
            };

            # Declarative Workspaces (Spaces)
            spaces = {
              "Dev" = {
                id = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
                icon = "📦";
                position = 1000;
                container = 1; # Dev container
              };
              "AI" = {
                id = "ai-2b9d4c41-6a8e-4c9b-9a44-6d1c7f2e8b02";
                icon = "🤖";
                position = 2000;
                container = 5; # AI container
              };
              "Gaming" = {
                id = "game-3c7e2b6d-9f5a-4b41-8f77-1e9c5a4d2c03";
                icon = "🎮";
                position = 3000;
                container = 4; # Gaming container
              };
              "Personal" = {
                id = "personal-4d8f3c7e-0a6b-5d52-9f88-2f0d6b5e3d14";
                icon = "🏠";
                position = 4000;
                container = 2; # Personal container
              };
              "Mining" = {
                id = "mining-5e9g4d8f-1b7c-6e63-0a99-3g1e7c6f4e25";
                icon = "⛏️";
                position = 5000;
                container = 3; # Finance container
              };
              "System" = {
                id = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
                icon = "⚙️";
                position = 6000;
                container = 2; # Personal container
              };
            };

            # Sidebar Pins (Essential sites)
            pins = {
              # Dev Space
              "GitHub" = {
                id = "pin-gh-001";
                url = "https://github.com";
                workspace = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
                container = 1;
                position = 100;
                isEssential = true;
              };
              "NixOS Wiki" = {
                id = "pin-nw-002";
                url = "https://nixos.wiki";
                workspace = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
                container = 1;
                position = 110;
              };

              # AI Space
              "Claude" = {
                id = "pin-ai-001";
                url = "https://claude.ai";
                workspace = "ai-2b9d4c41-6a8e-4c9b-9a44-6d1c7f2e8b02";
                container = 5;
                position = 200;
                isEssential = true;
              };
              "LM Studio" = {
                id = "pin-ai-002";
                url = "https://lmstudio.ai";
                workspace = "ai-2b9d4c41-6a8e-4c9b-9a44-6d1c7f2e8b02";
                container = 5;
                position = 210;
              };

              # Gaming Space
              "Discord" = {
                id = "pin-game-001";
                url = "https://discord.com";
                workspace = "game-3c7e2b6d-9f5a-4b41-8f77-1e9c5a4d2c03";
                container = 4;
                position = 300;
                isEssential = true;
              };
              "Steam" = {
                id = "pin-game-002";
                url = "https://store.steampowered.com";
                workspace = "game-3c7e2b6d-9f5a-4b41-8f77-1e9c5a4d2c03";
                container = 4;
                position = 310;
              };

              # Personal Space
              "Gmail" = {
                id = "pin-per-001";
                url = "https://mail.google.com";
                workspace = "personal-4d8f3c7e-0a6b-5d52-9f88-2f0d6b5e3d14";
                container = 2;
                position = 400;
              };
              "Outlook" = {
                id = "pin-per-003";
                url = "https://outlook.live.com/mail";
                workspace = "personal-4d8f3c7e-0a6b-5d52-9f88-2f0d6b5e3d14";
                container = 2;
                position = 405;
              };
              "Reddit" = {
                id = "pin-per-002";
                url = "https://reddit.com";
                workspace = "personal-4d8f3c7e-0a6b-5d52-9f88-2f0d6b5e3d14";
                container = 2;
                position = 410;
              };

              # Mining Space
              "NiceHash" = {
                id = "pin-min-001";
                url = "https://www.nicehash.com";
                workspace = "mining-5e9g4d8f-1b7c-6e63-0a99-3g1e7c6f4e25";
                container = 3;
                position = 500;
              };
              "MiningPoolStats" = {
                id = "pin-min-002";
                url = "https://miningpoolstats.stream";
                workspace = "mining-5e9g4d8f-1b7c-6e63-0a99-3g1e7c6f4e25";
                container = 3;
                position = 510;
              };

              # System Space
              "Tailscale" = {
                id = "pin-sys-001";
                url = "https://login.tailscale.com";
                workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
                container = 2;
                position = 600;
                isEssential = true;
              };
            };

            # Custom Search Engines with Aliases
            search = {
              force = true;
              default = "google";
              privateDefault = "ddg";
              order = [
                "google"
                "ddg"
                "github"
                "nixos-packages"
                "nixos-options"
                "nixos-wiki"
                "home-manager"
                "mynixos"
                "noogle"
                "huggingface"
                "pypi"
                "stackoverflow"
                "mdn"
              ];
              engines = {
                google = {
                  urls = [ { template = "https://www.google.com/search?q={searchTerms}"; } ];
                  icon = "https://www.google.com/favicon.ico";
                  definedAliases = [
                    "@g"
                    "@google"
                  ];
                };
                ddg = {
                  urls = [ { template = "https://duckduckgo.com/?q={searchTerms}"; } ];
                  icon = "https://duckduckgo.com/favicon.ico";
                  definedAliases = [
                    "@d"
                    "@ddg"
                  ];
                };
                github = {
                  urls = [ { template = "https://github.com/search?q={searchTerms}&type=repositories"; } ];
                  icon = "https://github.com/favicon.ico";
                  definedAliases = [
                    "@gh"
                    "@github"
                  ];
                };
                nixos-packages = {
                  urls = [
                    {
                      template = "https://search.nixos.org/packages";
                      params = [
                        {
                          name = "type";
                          value = "packages";
                        }
                        {
                          name = "query";
                          value = "{searchTerms}";
                        }
                      ];
                    }
                  ];
                  icon = "https://nixos.org/favicon.ico";
                  definedAliases = [
                    "@np"
                    "@nixpkgs"
                  ];
                };
                nixos-options = {
                  urls = [
                    {
                      template = "https://search.nixos.org/options";
                      params = [
                        {
                          name = "type";
                          value = "packages";
                        }
                        {
                          name = "query";
                          value = "{searchTerms}";
                        }
                      ];
                    }
                  ];
                  icon = "https://nixos.org/favicon.ico";
                  definedAliases = [
                    "@no"
                    "@nixopts"
                  ];
                };
                nixos-wiki = {
                  urls = [ { template = "https://nixos.wiki/index.php?search={searchTerms}"; } ];
                  icon = "https://nixos.wiki/favicon.ico";
                  definedAliases = [ "@nw" ];
                };
                home-manager = {
                  urls = [ { template = "https://home-manager-options.extranix.com/?query={searchTerms}"; } ];
                  icon = "https://nixos.org/favicon.ico";
                  definedAliases = [ "@hm" ];
                };
                mynixos = {
                  urls = [ { template = "https://mynixos.com/search?q={searchTerms}"; } ];
                  icon = "https://mynixos.com/favicon.ico";
                  definedAliases = [
                    "@mn"
                    "@mynixos"
                  ];
                };
                noogle = {
                  urls = [ { template = "https://noogle.dev/q?term={searchTerms}"; } ];
                  icon = "https://nixos.org/favicon.ico";
                  definedAliases = [
                    "@ng"
                    "@noogle"
                  ];
                };
                huggingface = {
                  urls = [ { template = "https://huggingface.co/search?q={searchTerms}"; } ];
                  icon = "https://huggingface.co/favicon.ico";
                  definedAliases = [
                    "@hf"
                    "@huggingface"
                  ];
                };
                pypi = {
                  urls = [ { template = "https://pypi.org/search/?q={searchTerms}"; } ];
                  icon = "https://pypi.org/favicon.ico";
                  definedAliases = [ "@pypi" ];
                };
                stackoverflow = {
                  urls = [ { template = "https://stackoverflow.com/search?q={searchTerms}"; } ];
                  icon = "https://stackoverflow.com/favicon.ico";
                  definedAliases = [
                    "@so"
                    "@stack"
                  ];
                };
                mdn = {
                  urls = [ { template = "https://developer.mozilla.org/en-US/search?q={searchTerms}"; } ];
                  icon = "https://developer.mozilla.org/favicon.ico";
                  definedAliases = [ "@mdn" ];
                };
              };
            };
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
            After = [
              "graphical-session-pre.target"
              "fix-vesktop-symlink.service"
            ];
            PartOf = [ "graphical-session.target" ];
            Wants = [ "fix-vesktop-symlink.service" ];
            XDG-Autostart = "true"; # Enable as XDG autostart
          };
          Service = {
            Type = "simple";
            ExecStart = "${pkgs.vesktop}/bin/vesktop --enable-speech-dispatcher --enable-features=UseOzonePlatform --ozone-platform-hint=auto --start-minimized";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };

        # Fix nixcord's read-only symlink issue
        # Vesktop needs to write to settings/settings.json but nixcord creates
        # a read-only symlink to Nix store. This service removes it after activation.
        systemd.user.services.fix-vesktop-symlink = {
          Unit = {
            Description = "Remove nixcord's read-only vesktop symlink";
            After = [ "home-manager-activate.service" ];
            Before = [ "vesktop-autostart.service" ];
            Requires = [ "home-manager-activate.service" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.writeShellScript "fix-vesktop-symlink" ''
              # Remove the problematic symlink if it exists
              if [ -L "$HOME/.config/vesktop/settings/settings.json" ]; then
                rm "$HOME/.config/vesktop/settings/settings.json"
                echo "Removed nixcord symlink for vesktop settings.json"
              fi
            ''}";
          };
        };
      };
  };

  # ============================================================================
  # FIREWALL
  # ============================================================================
  networking.firewall = {
    allowedTCPPorts = [
      9757 # WiVRn
      18789
      18790
      19898
    ];
    allowedUDPPorts = [
      9757 # WiVRn
      9758
      9759
      27031
      27036
      5353 # mDNS
      9947 # WiVRn
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
