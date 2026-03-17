# Zen Browser Configuration (Home Manager)
# Declarative browser configuration with extensions, containers, workspaces, and search engines
{pkgs, ...}: {
  # Mask Vesktop XDG autostart file to prevent SIGILL crash
  # The XDG autostart uses the wrong Electron binary (unwrapped vs wrapped)
  # We use systemd user service instead for proper autostart
  xdg.configFile."autostart/vesktop.desktop".text = ''
    [Desktop Entry]
    Hidden=true
    X-GNOME-Autostart-enabled=false
    X-KDE-autostart-after-panel=false
  '';

  # XDG MIME associations - make Zen the default browser for all web protocols
  # NOTE: Desktop file is named zen-twilight.desktop (not zen-browser.desktop)
  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    "text/html" = "zen-twilight.desktop";
    "text/xml" = "zen-twilight.desktop";
    "application/xhtml+xml" = "zen-twilight.desktop";
    "application/vnd.mozilla.xul+xml" = "zen-twilight.desktop";
    "text/mml" = "zen-twilight.desktop";
    "application/rss+xml" = "zen-twilight.desktop";
    "application/rdf+xml" = "zen-twilight.desktop";
    "x-scheme-handler/http" = "zen-twilight.desktop";
    "x-scheme-handler/https" = "zen-twilight.desktop";
    "x-scheme-handler/ftp" = "zen-twilight.desktop";
    "x-scheme-handler/chrome" = "zen-twilight.desktop";
    "x-scheme-handler/about" = "zen-twilight.desktop";
    "x-scheme-handler/unknown" = "zen-twilight.desktop";
    "x-scheme-handler/webcal" = "zen-twilight.desktop";
    "x-scheme-handler/mailto" = "zen-twilight.desktop";  # For web email
    "x-scheme-handler/irc" = "zen-twilight.desktop";      # For web IRC clients
  };

  programs.zen-browser = {
    enable = true;

    # Native Messaging Hosts - bridge browser to native apps
    nativeMessagingHosts = with pkgs; [
      firefoxpwa  # PWA support - install websites as apps
    ];

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

      # DNS-over-HTTPS - encrypted DNS queries
      DNSOverHTTPS = {
        Enabled = true;
        Locked = true;
        ProviderURL = "https://security.cloudflare-dns.com/dns-query";
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
        "containe@search.uky.edu" = {
          installation_mode = "normal_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/containerise/latest.xpi";
        };
      };
    };

    profiles.default = {
      id = 0;
      name = "default";
      isDefault = true;

      # Allow manual changes to declarative settings
      # Setting to false prevents Zen from resetting your customizations
      containersForce = false;
      pinsForce = false;
      spacesForce = false;

      # Custom about:config preferences
      extraConfig = ''
        // Zen-specific preferences
        user_pref("zen.theme.sidebar", "auto");
        user_pref("zen.view.compact", true);
        user_pref("zen.workspaces.vertical", true);

        // Dark mode - signal to websites that system prefers dark mode
        // This enables native dark themes on supporting websites via CSS prefers-color-scheme
        user_pref("ui.systemUsesDarkTheme", 1);
        user_pref("browser.in-content.dark-mode", true);
        user_pref("layout.css.prefers-color-scheme.content-override", 2); // 2 = dark

        // Zen theme mode - follow system dark/light preference
        user_pref("zen.theme.mode", "system");

        // Performance optimizations
        user_pref("gfx.webrender.all", true);
        user_pref("media.ffmpeg.vaapi.enabled", true);
        // TESTING: Re-enabled widget.dmabuf.force-enabled to test if NVIDIA + Wayland issues are resolved
        // If WebGL/Canvas corruption occurs (e.g., Facebook Messenger), comment this out again
        user_pref("widget.dmabuf.force-enabled", true);

        // Privacy enhancements
        user_pref("privacy.resistFingerprinting", true);
        user_pref("network.http.referer.spoofSource", true);
        user_pref("privacy.trackingprotection.enabled", true);

        // HTTPS-only mode - always use secure connections
        user_pref("dom.security.https_only_mode", true);
        user_pref("dom.security.https_only_mode_ever_enabled", true);
        user_pref("dom.security.https_only_mode_send_http_background_request", false);

        // Enhanced cookie isolation - prevent cross-site tracking
        user_pref("network.cookie.cookieBehavior", 5); // Block third-party + isolate first-party

        // GPU acceleration for AI/ML web apps
        user_pref("gfx.webrender.compositor", true);
        user_pref("layers.gpu-process.enabled", true);
        user_pref("media.hardware-video-decoding.enabled", true);

        // Increase cache for large web apps
        user_pref("browser.cache.disk.capacity", 1048576);  // 1GB
        user_pref("browser.cache.memory.capacity", 65536);   // 64MB

        // Tab grouping - auto-group by domain
        user_pref("zen.tab.grouping.enabled", true);

        // Web activity tracking - see time spent per site
        user_pref("zen.web-activity.enabled", true);
        user_pref("zen.web-activity.show-in-sidebar", true);
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
        "Temporary" = {
          color = "blue";
          icon = "cart";
          id = 6;
        };
        "Clients" = {
          color = "pink";
          icon = "circle";
          id = 7;
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
        "Clients" = {
          id = "clients-7h1i2j3k-4l5m-6n7o-8p9q-0r1s2t3u4v5w6";
          icon = "💼";
          position = 5500;
          container = 7; # Clients container
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
        };
        "NixOS Wiki" = {
          id = "pin-nw-002";
          url = "https://nixos.wiki";
          workspace = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
          container = 1;
          position = 110;
        };
        "Reverb256" = {
          id = "pin-dev-003";
          url = "https://reverb256.github.io";
          workspace = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
          container = 1;
          position = 115;
        };

        # AI Space
        "Claude" = {
          id = "pin-ai-001";
          url = "https://claude.ai";
          workspace = "ai-2b9d4c41-6a8e-4c9b-9a44-6d1c7f2e8b02";
          container = 5;
          position = 200;
        };
        "LM Studio" = {
          id = "pin-ai-002";
          url = "https://lmstudio.ai";
          workspace = "ai-2b9d4c41-6a8e-4c9b-9a44-6d1c7f2e8b02";
          container = 5;
          position = 210;
        };
        "Hugging Face" = {
          id = "pin-ai-003";
          url = "https://huggingface.co";
          workspace = "ai-2b9d4c41-6a8e-4c9b-9a44-6d1c7f2e8b02";
          container = 5;
          position = 215;
        };
        "Civitai" = {
          id = "pin-ai-004";
          url = "https://civitai.com";
          workspace = "ai-2b9d4c41-6a8e-4c9b-9a44-6d1c7f2e8b02";
          container = 5;
          position = 220;
        };

        # Gaming Space
        "Discord" = {
          id = "pin-game-001";
          url = "https://discord.com";
          workspace = "game-3c7e2b6d-9f5a-4b41-8f77-1e9c5a4d2c03";
          container = 4;
          position = 300;
        };
        "Steam" = {
          id = "pin-game-002";
          url = "https://store.steampowered.com";
          workspace = "game-3c7e2b6d-9f5a-4b41-8f77-1e9c5a4d2c03";
          container = 4;
          position = 310;
        };

        # Clients Space
        "TrovesAndCoves" = {
          id = "pin-client-001";
          url = "https://trovesandcoves.ca";
          workspace = "clients-7h1i2j3k-4l5m-6n7o-8p9q-0r1s2t3u4v5w6";
          container = 7;
          position = 350;
        };
        "TrovesAndCoves Etsy" = {
          id = "pin-client-002";
          url = "https://www.etsy.com/ca/shop/TrovesAndCoves";
          workspace = "clients-7h1i2j3k-4l5m-6n7o-8p9q-0r1s2t3u4v5w6";
          container = 7;
          position = 355;
        };
        "Hair At Home" = {
          id = "pin-client-003";
          url = "https://reverb256.github.io/hairathome";
          workspace = "clients-7h1i2j3k-4l5m-6n7o-8p9q-0r1s2t3u4v5w6";
          container = 7;
          position = 360;
        };
        "TrovesAndCoves Repo" = {
          id = "pin-client-004";
          url = "https://github.com/reverb256/trovesandcoves";
          workspace = "clients-7h1i2j3k-4l5m-6n7o-8p9q-0r1s2t3u4v5w6";
          container = 7;
          position = 365;
        };
        "HairAtHome Repo" = {
          id = "pin-client-005";
          url = "https://github.com/reverb256/hairathome";
          workspace = "clients-7h1i2j3k-4l5m-6n7o-8p9q-0r1s2t3u4v5w6";
          container = 7;
          position = 370;
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

        # Mining Space
        "Kryptex" = {
          id = "pin-min-001";
          url = "https://kryptex.com";
          workspace = "mining-5e9g4d8f-1b7c-6e63-0a99-3g1e7c6f4e25";
          container = 3;
          position = 500;
        };

        # System Space
        "Tailscale" = {
          id = "pin-sys-001";
          url = "https://login.tailscale.com";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 600;
        };
        "Grafana" = {
          id = "pin-sys-002";
          url = "http://zephyr.lan:3001";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 610;
        };
        "Prometheus" = {
          id = "pin-sys-003";
          url = "http://zephyr.lan:9090";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 615;
        };
        "AlertManager" = {
          id = "pin-sys-004";
          url = "http://zephyr.lan:9093";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 620;
        };
        "AI Gateway" = {
          id = "pin-sys-005";
          url = "http://zephyr.lan:8080";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 625;
        };
        "Spacebot" = {
          id = "pin-sys-006";
          url = "http://zephyr.lan:19898";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 630;
        };
        "Switch 1" = {
          id = "pin-sys-007";
          url = "http://10.1.1.10";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 635;
        };
        "Switch 2" = {
          id = "pin-sys-008";
          url = "http://10.1.1.11";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 640;
        };
        "Switch 3" = {
          id = "pin-sys-009";
          url = "http://10.1.1.12";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 645;
        };
        "Switch 4" = {
          id = "pin-sys-010";
          url = "http://10.1.1.13";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 650;
        };
        "Vaultwarden" = {
          id = "pin-sys-011";
          url = "https://vaultwarden.zephyr.tigris-ule.ts.net";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 655;
        };
        "Garage S3 (Nexus)" = {
          id = "pin-sys-012";
          url = "http://nexus.lan:3900";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 660;
        };
        "Llamafile" = {
          id = "pin-sys-013";
          url = "http://zephyr.lan:8083";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 665;
        };
        "Syncthing (Zephyr)" = {
          id = "pin-sys-014";
          url = "http://127.0.0.1:8384";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 670;
        };
        "SearXNG" = {
          id = "pin-sys-015";
          url = "http://127.0.0.1:7777";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 675;
        };
        "Host Dashboard (Zephyr)" = {
          id = "pin-sys-016";
          url = "http://zephyr.lan:8090";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 680;
        };
        "Host Dashboard (Nexus)" = {
          id = "pin-sys-017";
          url = "http://nexus.lan:8090";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 685;
        };
        "Host Dashboard (Forge)" = {
          id = "pin-sys-018";
          url = "http://forge.lan:8090";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 690;
        };
        "Host Dashboard (Sentry)" = {
          id = "pin-sys-019";
          url = "http://sentry.lan:8090";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 695;
        };
        "GitHub Actions (TrovesAndCoves)" = {
          id = "pin-sys-020";
          url = "https://github.com/reverb256/trovesandcoves/actions";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 700;
        };
        "GitHub Actions (HairAtHome)" = {
          id = "pin-sys-021";
          url = "https://github.com/reverb256/hairathome/actions";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 705;
        };
        "GitHub Actions (Reverb256)" = {
          id = "pin-sys-022";
          url = "https://github.com/reverb256/reverb256.github.io/actions";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 710;
        };
        "GitHub Actions (Frostbite)" = {
          id = "pin-sys-023";
          url = "https://github.com/reverb256/frostbite-gazette/actions";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 715;
        };
        "Cloudflare" = {
          id = "pin-sys-024";
          url = "https://dash.cloudflare.com";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 720;
        };
        "Namecheap" = {
          id = "pin-sys-025";
          url = "https://www.namecheap.com";
          workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
          container = 2;
          position = 725;
        };
      };

      # Custom Search Engines with Aliases
      search = {
        force = true;
        default = "searxng";
        privateDefault = "searxng";
        order = [
          "searxng"
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
            urls = [{template = "https://www.google.com/search?q={searchTerms}";}];
            icon = "https://www.google.com/favicon.ico";
            definedAliases = [
              "@g"
              "@google"
            ];
          };
          ddg = {
            urls = [{template = "https://duckduckgo.com/?q={searchTerms}";}];
            icon = "https://duckduckgo/favicon.ico";
            definedAliases = [
              "@d"
              "@ddg"
            ];
          };
          github = {
            urls = [{template = "https://github.com/search?q={searchTerms}&type=repositories";}];
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
            urls = [{template = "https://nixos.wiki/index.php?search={searchTerms}";}];
            icon = "https://nixos.wiki/favicon.ico";
            definedAliases = ["@nw"];
          };
          home-manager = {
            urls = [{template = "https://home-manager-options.extranix.com/?query={searchTerms}";}];
            icon = "https://nixos.org/favicon.ico";
            definedAliases = ["@hm"];
          };
          mynixos = {
            urls = [{template = "https://mynixos.com/search?q={searchTerms}";}];
            icon = "https://mynixos.com/favicon.ico";
            definedAliases = [
              "@mn"
              "@mynixos"
            ];
          };
          noogle = {
            urls = [{template = "https://noogle.dev/q?term={searchTerms}";}];
            icon = "https://nixos.org/favicon.ico";
            definedAliases = [
              "@ng"
              "@noogle"
            ];
          };
          huggingface = {
            urls = [{template = "https://huggingface.co/search?q={searchTerms}";}];
            icon = "https://huggingface.co/favicon.ico";
            definedAliases = [
              "@hf"
              "@huggingface"
            ];
          };
          pypi = {
            urls = [{template = "https://pypi.org/search/?q={searchTerms}";}];
            icon = "https://pypi.org/favicon.ico";
            definedAliases = ["@pypi"];
          };
          stackoverflow = {
            urls = [{template = "https://stackoverflow.com/search?q={searchTerms}";}];
            icon = "https://stackoverflow.com/favicon.ico";
            definedAliases = [
              "@so"
              "@stack"
            ];
          };
          mdn = {
            urls = [{template = "https://developer.mozilla.org/en-US/search?q={searchTerms}";}];
            icon = "https://developer.mozilla.org/favicon.ico";
            definedAliases = ["@mdn"];
          };
          searxng = {
            urls = [{template = "http://127.0.0.1:7777/search?q={searchTerms}";}];
            icon = "https://searxng.org/static/img/logo_small.svg";
            definedAliases = [
              "@sx"
              "@searxng"
            ];
          };
        };
      };
    };
  };
}
