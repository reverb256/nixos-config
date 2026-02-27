{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [
    inputs.zen-browser.homeModules.default
    inputs.nixcord.homeModules.nixcord
    ./modules/desktop/hyprland/home.nix

    # Shell (starship is Home Manager compatible)
    ./modules/shell/starship.nix

    # Note: niri home.nix, fish.nix, and rust.nix are imported in system configuration, not here
  ];

  # Stylix home-manager integration - must match system-level config
  # System-level config is in flake.nix with same theme
  stylix = {
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyo-city-terminal-dark.yaml";
  };

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

    # Stylix fonts (also configured in stylix.fonts above)
    inter
    pkgs.nerd-fonts.jetbrains-mono
    noto-fonts-color-emoji
    dejavu_fonts

    # Nix development tools (keep global for NixOS management)
    alejandra
    deadnix
    statix
    nixd
    cmake # CMake build system

    # User applications
    opencode
    qwen-code
    inputs.self.packages.x86_64-linux.claude
    gh
    gparted
    # yakuake  # KDE dropdown terminal - temporarily disabled, package may not be available
    # localsend - moved to system config (programs.localsend with firewall)
    jocalsend # TUI client for LocalSend (uses same port)

    #  AI agent
    # Cloud and sync tools
    rclone
    rclone-browser
    restic
    tailscale

    # From nix profile (moved to declarative)
    gpu-viewer
    cachix

    # CLI tools
    _1password-cli # 1Password CLI
    himalaya # Email CLI
    spotify-player # Spotify TUI

    # Media tools (moved from system-packages)
    yt-dlp

    # Display management (moved from system-packages)
    kanshi
    jq # JSON processor for monitor config scripts

    # Kilo CLI wrapper
    (pkgs.writeShellScriptBin "kilo" ''
      exec ${pkgs.nodejs_22}/bin/npx @kilocode/cli "$@"
    '')

    # ClawHub CLI for  skill management
    (pkgs.writeShellScriptBin "clawdhub" ''
      exec ${pkgs.nodejs_22}/bin/npx clawdhub "$@"
    '')
  ];

  home.sessionVariables = {
    # MCP Configuration
    MCP_ENABLED = "true";
    OPENCODE_MCP_SCHEMA_FIX = "1";

    API_TIMEOUT_MS = "3000000";

    # API key files (from Agenix secrets)
    # Note: These files must exist in secrets/ directory and be configured in secrets/age-secrets.nix
    OPENROUTER_API_KEY_FILE = "/run/agenix/openrouter-api-key";

    # OpenCode environment variables
    OPENCODE_TOOL_STRUCTURED_OUTPUT = "1";
    OPENCODE_PATH_FIX = "1";

    # GLM Coding Plan - Model Mappings for Claude Code
    # Maps Claude Code's model tiers to GLM models
    # Opus tier = GLM-5 (best for complex reasoning, large-scale refactoring)
    # Sonnet tier = GLM-4.7 (balanced for daily development)
    # Haiku tier = GLM-4.5-Air (fastest for simple tasks)
    ANTHROPIC_DEFAULT_OPUS_MODEL = "glm-5";
    ANTHROPIC_DEFAULT_SONNET_MODEL = "glm-4.7";
    ANTHROPIC_DEFAULT_HAIKU_MODEL = "glm-4.5-air";
  };

  # Zen Browser configuration - Enhanced privacy and productivity setup
  programs.zen-browser = {
    enable = true;

    # Profile definitions for Stylix theming
    # Using the actual active profile (w26i4er3) that zen-browser uses
    profiles.default = {
      isDefault = true;
      id = 0;
      name = "Default Profile";
      path = "w26i4er3.Default Profile";
      settings = {
        "zen.welcome-screen.seen" = true;
        # Force dark theme to bypass xdg-desktop-portal detection
        "layout.css.prefers-color-scheme.content-override" = 0;
      };
    };

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

      # Override new tab page
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

  # Stylix theming - Apply Tokyo City Dark theme to all applications
  stylix.targets = {
    # Browser
    zen-browser.profileNames = [ "default" ];

    # Shell and Prompt
    fish.enable = true;
    starship.enable = true;

    # Terminal Tools
    bat.enable = true;
    fzf.enable = true;
    tmux.enable = true;

    # Editor
    neovim.enable = true;
    vim.enable = true;

    # Desktop Environment
    gtk.enable = true;
    # Disable Stylix Qt theming - it generates Kvantum configs that cause "module kvantum is not installed" errors
    # Plasma 6 handles Qt theming natively via "kde" platform
    qt.enable = false;
  };

  # Program configurations
  programs = {
    # Git configuration
    git = {
      enable = true;
      settings = {
        user.name = "Jeremy Kroeker";
        user.email = "j_kroeker@reverb256.ca";
        init.defaultBranch = "main";
        pull.rebase = false;
        # Optimization settings for distributed fleet operations
        fetch.prune = true;
        fetch.parallel = 4;
        core.compression = 9;
        # Additional performance optimizations (camelCase for nested settings)
        core.preloadIndex = true;
        core.untrackedCache = true;
      };
    };

    # SSH configuration - Managed centrally by modules/ssh.nix (NixOS system module)
    # Home Manager SSH is disabled to avoid conflicts with system-level SSH config

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
      historyControl = [
        "ignoredups"
        "ignorespace"
      ];
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
      enable = false;
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

    # OpenVR paths for Steam integration with xrizer (OpenVR -> OpenXR translation)
    # xrizer is newer and better maintained than OpenComposite
    # WiVRn handles the openvr-compat-path in its own config.json

    configFile."openvr/openvrpaths.vrpath" = {
      force = true;
      text =
        let
          xrizer = "${pkgs.xrizer}/lib/xrizer";
          steam = "$HOME/.local/share/Steam";
        in
        builtins.toJSON {
          version = 1;
          jsonid = "vrpathreg";
          external_drivers = null;
          config = [ "${steam}/config" ];
          log = [ "${steam}/logs" ];
          runtime = [ "${xrizer}" ];
        };
    };

    # Using WiVRn as OpenXR runtime
    # This sets WiVRn as active OpenXR runtime for all OpenXR apps
    configFile."openxr/1/active_runtime.json" = {
      source = "${pkgs.wivrn}/share/openxr/1/openxr_wivrn.json";
      force = true;
    };

    # Konsole theming (Stylix doesn't have native Konsole support)
    # Generate Konsole color scheme from Stylix colors
    configFile."konsole/Stylix.colorscheme".text =
      let
        c = config.lib.stylix.colors;
      in
      ''
        [Background]
        Color=${builtins.substring 1 6 c.base00}

        [BackgroundIntense]
        Color=${builtins.substring 1 6 c.base01}

        [Color0]
        Color=${builtins.substring 1 6 c.base00}

        [Color0Intense]
        Color=${builtins.substring 1 6 c.base01}

        [Color1]
        Color=${builtins.substring 1 6 c.base08}

        [Color1Intense]
        Color=${builtins.substring 1 6 c.base08}

        [Color2]
        Color=${builtins.substring 1 6 c.base0B}

        [Color2Intense]
        Color=${builtins.substring 1 6 c.base0B}

        [Color3]
        Color=${builtins.substring 1 6 c.base0A}

        [Color3Intense]
        Color=${builtins.substring 1 6 c.base0A}

        [Color4]
        Color=${builtins.substring 1 6 c.base0D}

        [Color4Intense]
        Color=${builtins.substring 1 6 c.base0D}

        [Color5]
        Color=${builtins.substring 1 6 c.base0E}

        [Color5Intense]
        Color=${builtins.substring 1 6 c.base0E}

        [Color6]
        Color=${builtins.substring 1 6 c.base0C}

        [Color6Intense]
        Color=${builtins.substring 1 6 c.base0C}

        [Color7]
        Color=${builtins.substring 1 6 c.base05}

        [Color7Intense]
        Color=${builtins.substring 1 6 c.base06}

        [Foreground]
        Color=${builtins.substring 1 6 c.base05}

        [ForegroundIntense]
        Color=${builtins.substring 1 6 c.base06}

        [General]
        Description=Stylix
        Opacity=1
      '';

    configFile."konsole/Stylix.profile".text = ''
      [Appearance]
      ColorScheme=Stylix
      Font=${config.stylix.fonts.monospace.name},${toString config.stylix.fonts.sizes.terminal}

      [General]
      Name=Stylix
      Parent=FALLBACK/
    '';

    # Note: konsolerc default profile is set via home.activation because Konsole
    # needs to write runtime state to this file. home.activation creates a writable
    # copy that Konsole can modify.
  };

  # Create writable konsolerc with default profile
  home.activation.konsolercWritable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Create directory if it doesn't exist
        mkdir -p $HOME/.config

        # Write konsolerc with default profile (only if file doesn't exist or is a symlink)
        if [ ! -e "$HOME/.config/konsolerc" ] || [ -L "$HOME/.config/konsolerc" ]; then
          cat > "$HOME/.config/konsolerc" <<EOF
    [Desktop Entry]
    DefaultProfile=Stylix.profile
    EOF
        fi
  '';

  # Claude Code KwaiKAT Model Development Tool Configuration
  # API key is loaded from system environment via modules/environment.nix

  # Nixcord (Discord) - uses Vesktop
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

  # PATH for user services is automatically managed by Home Manager
  # systemd.user.sessionVariables.PATH is not needed - HM sets this correctly

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

  # KScreen monitor configuration by EDID (manufacturer + model)
  # This ensures monitors keep their priorities regardless of port changes
  #
  # Priority order:
  #   1. ZOWIE (BenQ/BNQ) - primary gaming display
  #   2. ASUS VT229 (AUS) - secondary display
  #   3. Acer X203H (ACR) - tertiary display
  #   4. Samsung (SAM) - lowest priority (large 4K TV)
  systemd.user.services.kscreen-edid-setup = {
    Unit = {
      Description = "Set KScreen monitor priorities by EDID";
      After = [ "graphical-session-pre.target" "plasma-kscreen.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = toString (pkgs.writeShellScript "kscreen-edid-setup" ''
        #!${pkgs.bash}/bin/bash
        set -e

        KSCREEN_CONFIG="$HOME/.local/share/kscreen/monitors.json"
        MAPPING_FILE=$(mktemp)

        # Wait for KScreen to create the config file
        for i in {1..30}; do
          [[ -f "$KSCREEN_CONFIG" ]] && break
          sleep 1
        done

        [[ ! -f "$KSCREEN_CONFIG" ]] && exit 1

        # Get manufacturer from EDID for a connector
        get_mfg() {
          local conn="$1"
          local edid="/sys/class/drm/card1-$conn/edid"
          [[ -f "$edid" ]] && ${pkgs.edid-decode}/bin/edid-decode "$edid" 2>/dev/null | grep "Manufacturer:" | awk '{print $2}'
        }

        # Get priority by manufacturer
        get_prio() {
          local mfg="$1"
          case "$mfg" in
            BNQ) echo 1 ;;  # ZOWIE (BenQ)
            AUS) echo 2 ;;  # ASUS
            ACR) echo 3 ;;  # Acer
            SAM) echo 4 ;;  # Samsung
            *)   echo 99 ;; # Unknown
          esac
        }

        # Create connector-to-priority mapping (avoid subshell issue)
        ${pkgs.jq}/bin/jq -r '.outputs[] | select(.enabled==true) | .name' "$KSCREEN_CONFIG" | while read -r conn; do
          mfg=$(get_mfg "$conn" || echo "UNK")
          prio=$(get_prio "$mfg")
          echo "$conn:$prio"
        done > "$MAPPING_FILE"

        # Build jq filter from mapping file
        jq_filter=".outputs |= map("
        first=true

        while IFS=: read -r conn prio; do
          if $first; then
            jq_filter+="if .name==\"$conn\" then .priority=$prio"
            first=false
          else
            jq_filter+=" elif .name==\"$conn\" then .priority=$prio"
          fi
        done < "$MAPPING_FILE"

        rm -f "$MAPPING_FILE"
        jq_filter+=" else .priority end)"

        # Update config atomically with unlock/re-lock
        ${pkgs.jq}/bin/jq "$jq_filter" "$KSCREEN_CONFIG" > "$KSCREEN_CONFIG.tmp"
        sudo chattr -i "$KSCREEN_CONFIG" 2>/dev/null || true
        mv "$KSCREEN_CONFIG.tmp" "$KSCREEN_CONFIG"
        sudo chattr +i "$KSCREEN_CONFIG" 2>/dev/null || true
      '');
      RemainAfterExit = true;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Sync zen-browser config from XDG (~/.config/zen) to legacy path (~/.zen)
  # Zen Browser reads from ~/.zen but Home Manager writes to ~/.config/zen
  home.activation.syncZenConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ZEN_PROFILE="w26i4er3.Default Profile"
    if [ -d "$HOME/.config/zen/$ZEN_PROFILE" ]; then
      mkdir -p "$HOME/.zen/$ZEN_PROFILE/chrome"
      cp -fL "$HOME/.config/zen/$ZEN_PROFILE/user.js" "$HOME/.zen/$ZEN_PROFILE/" 2>/dev/null || true
      cp -fL "$HOME/.config/zen/$ZEN_PROFILE/chrome/userChrome.css" "$HOME/.zen/$ZEN_PROFILE/chrome/" 2>/dev/null || true
      cp -fL "$HOME/.config/zen/$ZEN_PROFILE/chrome/userContent.css" "$HOME/.zen/$ZEN_PROFILE/chrome/" 2>/dev/null || true
    fi
  '';
}
