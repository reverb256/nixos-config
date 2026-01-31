{
  pkgs,
  inputs,
  ...
}: {
  # Import Zen Browser and Nixcord (Home Manager modules)
  imports = [
    inputs.zen-browser.homeModules.default
    inputs.nixcord.homeModules.nixcord
  ];

  # NH (Nix Helper) configuration for better UX
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d --keep 5";
    };
    # Home Manager specific flake location
    flake = "/etc/nixos";
  };

  # Enhanced Home Manager configuration with web search support
  home = {
    username = "j_kro";
    homeDirectory = "/home/j_kro";
    stateVersion = "26.05";
  };

  # User packages - development tools, shell utilities, and applications
  home.packages = with pkgs; [
    # Shell tools (configured in programs section below)
    btop
    fzf
    tmux
    eza
    zoxide
    starship

    # Development tools
    alejandra
    deadnix
    statix
    nixd
    basedpyright
    bash-language-server
    nodePackages.typescript-language-server

    # User applications
    opencode
    qwen-code
    gh
    gparted

    # Cloud and sync tools
    rclone
    rclone-browser
    restic
    tailscale

    # Node.js for various tools
    nodejs_22

    # ML/AI Tools - PyTorch/TensorFlow removed to avoid long compilation
    # Use nix shell when needed: nix shell nixpkgs#python312Packages.torchWithCuda
    python312

    # From nix profile (moved to declarative)
    gpu-viewer
    cachix

    # Bun - Fast JavaScript runtime and package manager
    bun

    # Go - Required for many OpenClaw skills
    go

    # OpenClaw skill dependencies
    _1password-cli      # 1Password CLI for 1password skill
    himalaya            # Email CLI for himalaya skill
    spotify-player      # Spotify TUI for spotify-player skill
    # TODO: Package these for NixOS or install via npm:
    # - bird (Twitter/X CLI)
    # - blogwatcher (RSS feed monitor)
    # - camsnap (RTSP camera capture)
    # - summarize (URL/content summarizer)

    # Media tools (moved from system-packages)
    yt-dlp

    # Display management (moved from system-packages)
    kanshi

    # Kilo CLI wrapper
    (pkgs.writeShellScriptBin "kilo" ''
      exec ${pkgs.nodejs_22}/bin/npx @kilocode/cli "$@"
    '')

    # OpenClaw - AI assistant (installed via npm)
    # Run: openclaw onboard
    (pkgs.writeShellScriptBin "openclaw" ''
      exec ${pkgs.nodejs_22}/bin/npx openclaw "$@"
    '')

    # ClawdHub - OpenClaw skill manager
    (pkgs.writeShellScriptBin "clawdhub" ''
      exec ${pkgs.nodejs_22}/bin/node ~/clawdhub-fix/node_modules/clawdhub/dist/cli.js "$@"
    '')
  ];

  # StreamLake Claude Code environment variables (enhanced with MCP)
  home.sessionVariables = {
    # MCP Server Configuration
    MCP_SERVER_URL = "http://localhost:3000";
    MCP_ENABLED = "true";
    WEB_SEARCH_ENABLED = "true";

    # StreamLake/Vanchin KAT-Coder-Pro-v1 configuration with proxy
    ANTHROPIC_BASE_URL = "https://vanchin.streamlake.ai/api/gateway/coding/kat-coder-pro-v1/claude-code-proxy";
    API_TIMEOUT_MS = "3000000";
    ANTHROPIC_MODEL = "kat-coder-pro-v1";

    # API key files (from Agenix secrets)
    ANTHROPIC_AUTH_TOKEN_FILE = "/run/agenix/claude-api-key";
    OPENROUTER_API_KEY_FILE = "/run/agenix/openrouter-api-key";
    OPENAI_API_KEY_FILE = "/run/agenix/openai-api-key";

    # OpenCode environment variables
    OPENCODE_MCP_SCHEMA_FIX = "1";
    OPENCODE_TOOL_STRUCTURED_OUTPUT = "1";
    OPENCODE_PATH_FIX = "1";
  };

  # Zen Browser configuration - Enhanced privacy and productivity setup
  programs.zen-browser = {
    enable = true;

    # Firefox-like policies and configuration
    policies = {
      # Disable telemetry and data collection
      DisableTelemetry = true;
      DisableFeedbackCommands = true;
      DisablePocket = true;
      DisableFirefoxStudies = true;
      DisableFirefoxAccounts = true;

      # Security and privacy settings
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
        Social = true;
      };

      # HTTPS-Only Mode
      HTTPSOnlyMode = "force_enabled";

      # DNS over HTTPS
      DNSOverHTTPS = {
        Enabled = true;
        ProviderURL = "https://mozilla.cloudflare-dns.com/dns-query";
        Locked = true;
      };

      # Cookies and site data
      Cookies = {
        Behavior = "reject_tracker";
        BehaviorPrivateBrowsing = "reject_tracker";
        ExpireAtSessionEnd = false;
      };

      # Extension settings - Essential privacy and productivity tools
      ExtensionSettings = {
        # uBlock Origin - Advanced ad blocker
        "uBlock0@raymondhill.net" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
        };

        # Bitwarden Password Manager
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
        };

        # Dark Reader - Dark mode for all websites
        "addon@darkreader.org" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
        };

        # Decentraleyes - Local CDN emulation
        "jid1-BoFifL9Vbdl2zQ@jetpack" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/decentraleyes/latest.xpi";
        };

        # Vimium - Keyboard navigation
        "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi";
        };

        # Plasma Browser Integration - KDE integration
        "plasma-browser-integration@kde.org" = {
          installation_mode = "force_installed";
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/plasma-browser-integration/latest.xpi";
        };
      };

      # Search engine settings - Privacy-focused defaults
      DefaultSearchEngine = "DuckDuckGo";
      SearchEngines = {
        Default = "DuckDuckGo";
        Remove = [
          "Google"
          "Bing"
          "Amazon.com"
          "eBay"
          "Twitter"
          "Wikipedia"
        ];
        Add = [
          {
            Name = "DuckDuckGo";
            URLTemplate = "https://duckduckgo.com/?q={searchTerms}";
            IconURL = "https://duckduckgo.com/favicon.ico";
            Alias = "@ddg";
          }
          {
            Name = "Nix Packages";
            URLTemplate = "https://search.nixos.org/packages?query={searchTerms}";
            IconURL = "https://wiki.nixos.org/favicon.ico";
            Alias = "@np";
          }
          {
            Name = "NixOS Options";
            URLTemplate = "https://search.nixos.org/options?query={searchTerms}";
            IconURL = "https://wiki.nixos.org/favicon.ico";
            Alias = "@no";
          }
          {
            Name = "NixOS Wiki";
            URLTemplate = "https://wiki.nixos.org/w/index.php?search={searchTerms}";
            IconURL = "https://wiki.nixos.org/favicon.ico";
            Alias = "@nw";
          }
          {
            Name = "GitHub";
            URLTemplate = "https://github.com/search?q={searchTerms}&type=repositories";
            IconURL = "https://github.com/favicon.ico";
            Alias = "@gh";
          }
        ];
      };

      # Homepage and new tab settings
      Homepage = {
        URL = "https://start.duckduckgo.com";
        Locked = false; # Allow user customization
      };

      # Override the new tab page
      NewTabPage = false;

      # Disable default browser check
      DontCheckDefaultBrowser = true;

      # Disable first run pages and tutorials
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      SkipDefaultBrowserCheck = true;

      # Performance settings
      preferences = {
        # Hardware acceleration
        "dom.webgpu.enabled" = true;
        "media.ffmpeg.vaapi.enabled" = true;

        # Memory management
        "browser.cache.memory.capacity" = 512000; # 512MB cache
        "browser.sessionstore.interval" = 15000; # Save session every 15s

        # UI performance
        "layout.css.grid-template-masonry-value.enabled" = true;
        "dom.enable_performance" = true;

        # Zen Browser specific settings
        "zen.tabs.vertical" = true; # Vertical tabs
        "zen.view.compact" = true; # Compact UI
        "zen.workspaces.enabled" = true; # Enable workspaces
        "zen.sidebar.enabled" = true; # Enable sidebar
      };

      # Container tabs configuration
      Containers = {
        Default = [
          {
            icon = "fingerprint";
            color = "blue";
            name = "Personal";
            id = 1;
          }
          {
            icon = "briefcase";
            color = "orange";
            name = "Work";
            id = 2;
          }
          {
            icon = "dollar";
            color = "green";
            name = "Banking";
            id = 3;
          }
          {
            icon = "cart";
            color = "pink";
            name = "Shopping";
            id = 4;
          }
        ];
      };
    };
  };

  # Program configurations
  programs = {
    # Git configuration
    git = {
      enable = true;
      settings = {
        user.name = "reverb256";
        user.email = "j_kroeker@reverb256.ca";
        init.defaultBranch = "master";
        pull.rebase = true;
      };
    };

    # Neovim configuration
    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
    };

    # Bash configuration
    bash = {
      enable = true;
      enableCompletion = true;
      historyControl = ["ignoredups" "ignorespace"];
      historySize = 10000;
      shellAliases = {
        ll = "ls -la";

        # NixOS rebuild aliases
        update = "sudo nixos-rebuild switch --flake /etc/nixos";
        build = "sudo nixos-rebuild build --flake /etc/nixos";
        test = "sudo nixos-rebuild test --flake /etc/nixos";

        # Justfile navigation and help
        j = "just --choose";
        help = "just help";
      };
    };

    # Fish configuration (Omarchy-inspired)
    fish = {
      enable = true;
      shellAliases = {
        ll = "eza -lh --group-directories-first --icons=auto";
        la = "eza -la --group-directories-first --icons=auto";
        l = "eza --group-directories-first --icons=auto";
        lt = "eza --tree --level=2 --long --icons --git";
      };
      interactiveShellInit = ''
        set -U fish_greeting ""
        eval "$(zoxide init fish)"
      '';
    };

    # Starship prompt (Omarchy minimal configuration)
    starship = {
      enable = true;
      settings = {
        format = "[$directory$git_branch$git_status]($style)$character";
        scan_timeout = 10;
        add_newline = false;

        character = {
          error_symbol = "[✗](bold cyan)";
          success_symbol = "[❯](bold cyan)";
        };

        directory = {
          truncation_length = 2;
          truncation_symbol = "…/";
          repo_root_style = "bold cyan";
          repo_root_format = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) ";
        };

        git_branch = {
          format = "[$branch]($style) ";
          style = "italic cyan";
        };

        git_status = {
          format = "[$all_status]($style)";
          style = "cyan";
          ahead = "⇡ ";
          behind = "⇣ ";
          diverged = "⇕ ";
          conflicted = "✖";
          untracked = "•";
          modified = "▲";
          staged = "●";
        };

        # Disable unused modules
        nix_shell.disabled = true;
        docker_context.disabled = true;
      };
    };

    # Zoxide - Smart cd (Omarchy-style)
    zoxide = {
      enable = true;
    };

    # FZF - Fuzzy finder with fish keybindings
    fzf = {
      enable = true;
      enableFishIntegration = true;
      enableBashIntegration = false;
    };

    # Direnv for project-specific environments
    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
  };

  # XDG user directories
  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
      documents = "$HOME/Documents";
      download = "$HOME/Downloads";
      music = "$HOME/Music";
      pictures = "$HOME/Pictures";
      videos = "$HOME/Videos";
      desktop = "$HOME/Desktop";
      publicShare = "$HOME/Public";
      templates = "$HOME/Templates";
    };

    # OpenVR paths for Steam integration with WiVRn

    configFile."openvr/openvrpaths.vrpath" = {
      force = true;
      text = let
        steam = "$HOME/.local/share/Steam";
      in
        builtins.toJSON {
          version = 1;
          jsonid = "vrpathreg";
          external_drivers = null;
          config = ["${steam}/config"];
          log = ["${steam}/logs"];
          "runtime" = ["$HOME/.local/share/openxr/1"];
        };
    };

    # WiVRn as default OpenXR runtime (primary VR runtime)
    configFile."openxr/1/active_runtime.json" = {
      source = "${pkgs.wivrn}/share/openxr/1/openxr_wivrn.json";
      force = true;
    };
  };

  # Claude Code KwaiKAT Model Development Tool Configuration
  # API key is loaded from system environment via modules/environment.nix

  # Clawbot is now system-level - remove from Home Manager
  # Configuration moved to configuration.nix

  # Minimal Nixcord (Discord client) configuration - uses Vesktop
  programs.nixcord = {
    enable = true;
    discord.enable = false; # Disable Discord, use Vesktop instead
    vesktop.enable = true; # Use Vesktop (Vencord + Wayland support)
  };

  # Autostart Vesktop on login
  systemd.user.services.vesktop-autostart = {
    Unit = {
      Description = "Vesktop autostart";
      After = ["graphical-session.target" "plasma-workspace.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.vesktop}/bin/vesktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };

  # DISABLED: Let KDE manage ksmserverrc directly (home-manager symlink is read-only)
  # Session restore is enabled via KDE System Settings instead
  # xdg.configFile."ksmserverrc" = { ... };

  # Kanshi - Dynamic display configuration for Wayland
  # Monitor Layout:
  # DP-2 (BenQ Zowie):    Top-left, primary gaming monitor
  # DP-1 (ASUS):          Top-right
  # DP-3 (Acer):          Bottom-right
  # HDMI-A-1 (Samsung):   Far right (TV)
  services.kanshi = {
    enable = true;
    settings = [
      {
        profile = {
          name = "default";
          outputs = [
            {
              criteria = "DP-2";
              position = "0,0";
              status = "enable";
            }
            {
              criteria = "DP-1";
              position = "1920,0";
              status = "enable";
            }
            {
              criteria = "DP-3";
              position = "1920,1080";
              status = "enable";
            }
            {
              criteria = "HDMI-A-1";
              position = "3840,0";
              status = "enable";
            }
          ];
        };
      }
    ];
  };
}
