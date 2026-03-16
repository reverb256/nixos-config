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
  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    "text/html" = "zen-browser.desktop";
    "text/xml" = "zen-browser.desktop";
    "application/xhtml+xml" = "zen-browser.desktop";
    "application/vnd.mozilla.xul+xml" = "zen-browser.desktop";
    "text/mml" = "zen-browser.desktop";
    "application/rss+xml" = "zen-browser.desktop";
    "application/rdf+xml" = "zen-browser.desktop";
    "x-scheme-handler/http" = "zen-browser.desktop";
    "x-scheme-handler/https" = "zen-browser.desktop";
    "x-scheme-handler/ftp" = "zen-browser.desktop";
    "x-scheme-handler/chrome" = "zen-browser.desktop";
    "x-scheme-handler/about" = "zen-browser.desktop";
    "x-scheme-handler/unknown" = "zen-browser.desktop";
    "x-scheme-handler/webcal" = "zen-browser.desktop";
    "x-scheme-handler/mailto" = "zen-browser.desktop";  # For web email
    "x-scheme-handler/irc" = "zen-browser.desktop";      # For web IRC clients
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
        };
        "NixOS Wiki" = {
          id = "pin-nw-002";
          url = "https://nixos.wiki";
          workspace = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
          container = 1;
          position = 110;
        };
        "TrovesAndCoves" = {
          id = "pin-dev-003";
          url = "https://trovesandcoves.ca";
          workspace = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
          container = 1;
          position = 115;
        };
        "Reverb256" = {
          id = "pin-dev-004";
          url = "https://reverb256.github.io";
          workspace = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
          container = 1;
          position = 116;
        };
        "Hair At Home" = {
          id = "pin-dev-005";
          url = "https://reverb256.github.io/hairathome";
          workspace = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
          container = 1;
          position = 117;
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
