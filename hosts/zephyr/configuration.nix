# Zephyr Host Configuration
# RTX 3090, Quest Pro, 4K HDR TV
{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    # ========================================================================
    # BASE MODULES
    # ========================================================================

    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # All other modules auto-imported via ../../modules/default.nix
    # This includes: system, desktop, shell, gaming, development, services,
    # plus zephyr-specific modules (nvidia-common, gstreamer, spotify, cluster networking)
    ../../modules/default.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "zephyr";

  # NVIDIA GPU support (RTX 3090 + 3060 Ti)
  hardware.nvidia-common.enable = true;

  # Hardware monitoring (lm-sensors, fan control for MSI X570)
  hardware.monitoring.enable = true;
  hardware.monitoring.autoDetect = false; # Skip auto-detect, we know the hardware
  hardware.monitoring.fanControl = false; # BIOS fan control for now

  networking.networkmanager.enable = true;

  # DNS - Use local unbound resolver for cluster hostnames
  services.unbound-cluster = {
    enable = true;
  };

  # Configure NetworkManager to use local unbound via connection settings
  networking.networkmanager.dns = "none";

  # Cluster hosts - populate /etc/hosts from cluster configuration
  networking.cluster-hosts = {
    enable = true;
    populateLocal = true;
  };

  # ============================================================================
  # WIRELESS HARDWARE
  # ============================================================================
  # WiFi support via wpa_supplicant (works with NetworkManager)
  networking.wireless.enable = true;

  # Bluetooth support via BlueZ
  hardware.bluetooth.enable = true;

  # Timezone and locale
  time.timeZone = "America/Winnipeg";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # Multi-GPU kernel modules for RTX 3090 + 3060 Ti
  boot.kernelModules = [
    "nvidia"
    "nvidia_uvm" # Unified Memory (CRITICAL for multi-GPU!)
    "nvidia_drm"
    "nvidia_modeset"
  ];

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

  # Podman container runtime (for Spacebot)
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  # Spacebot AI agent (integrated with AI Gateway)
  services.spacebot = {
    enable = true;
    useGateway = true;
    gatewayUrl = "http://127.0.0.1:8080";
    host = "127.0.0.1";
    port = 19898;
    memory = "4G";
    cpu = "2";

    # Provider API keys for LLM backends
    providerKeys = {
      ZAI_CODING_PLAN_KEY = "/run/agenix/zai-api-key";
      KILO_API_KEY = "/run/agenix/kilo-api-key";
    };

    # Discord integration - you need to set up the bot token
    # TEMPORARILY DISABLED: Secret file not yet created
    discord.enable = false;
    # discord.tokenFile = "/run/agenix/spacebot-discord-token";
    # discord.guildId = "YOUR_GUILD_ID";  # Optional: restrict to specific server
  };

  # Agenix secrets for AI services
  age.identityPaths = [ "/home/j_kro/.age/key.txt" ];

  age.secrets.lm-studio-api-key = {
    file = "${inputs.self}/secrets/lm-studio-api-key.age";
    mode = "440";
    owner = "ai-inference";
    group = "ai-inference";
  };

  age.secrets.huggingface-token = {
    file = "${inputs.self}/secrets/huggingface-token.age";
    mode = "440";
    owner = "j_kro";
    group = "users";
  };

  age.secrets.zai-api-key = {
    file = "${inputs.self}/secrets/zai-api-key.age";
    mode = "440";
    owner = "j_kro";
    group = "ai-inference";
  };

  # Kilo API key - Kilo Code provider for Spacebot
  age.secrets.kilo-api-key = {
    file = "${inputs.self}/secrets/kilo-api-key.age";
    mode = "440";
    owner = "j_kro";
    group = "users";
  };

  # Spacebot Discord bot token
  # TEMPORARILY DISABLED: Secret file not yet created
  # age.secrets.spacebot-discord-token = {
  #   file = "${inputs.self}/secrets/spacebot-discord-token.age";
  #   mode = "440";
  #   owner = "root";
  #   group = "root";
  # };

  # TODO: Re-enable switch-admin secret after fixing switch-orchestration module
  # age.secrets.switch-admin = {
  #   file = "${inputs.self}/secrets/switch-admin.age";
  #   mode = "440";
  #   owner = "root";
  #   group = "wheel";
  # };

  # ============================================================================
  # REDIS - For gateway rate limiting and caching
  # ============================================================================
  services.redis.servers."".enable = true;

  # ============================================================================
  # AI INFERENCE SERVICE - Gateway with authentication and metrics
  # Gateway routes to LM Studio backend with API token authentication
  # Backend: LM Studio on port 1234
  # Gateway: OpenAI-compatible API on port 8080
  # ============================================================================
  services.ai-inference = {
    enable = true;
    backend = {
      url = "http://127.0.0.1:1234"; # LM Studio on port 1234
      type = "lm-studio";
      lmStudio.apiKeyFile = "/run/agenix/lm-studio-api-key";
      # ZAI Coding Plan Max configuration
      # IMPORTANT: Use the dedicated Coding endpoint for GLM Coding Plan
      # Coding endpoint: https://api.z.ai/api/coding/paas/v4
      # General endpoint: https://api.z.ai/api/paas/v4 (billed separately, not Coding Plan)
      zai = {
        enable = true;
        apiKeyFile = "/run/agenix/zai-api-key";
        # Use coding endpoint for Coding Plan Max quota
        baseUrl = "https://api.z.ai/api/coding/paas/v4";
      };
    };
    gateway = {
      enable = true;
      host = "127.0.0.1";
      port = 8080;
      workers = 1; # Single worker for now (multi-worker has import issues)
    };
    routing = {
      enable = true;
      defaultModel = "magnum-opus-35b-a3b-i1";
      fallbackChain = [
        "vllm"
        "lm-studio"
        "zai"
      ];
    };
    auth.mode = "none"; # Disabled for testing - change back to "api-key" for production
    monitoring.enable = true;
    # Disable security proxy for local development (too aggressive for code)
    rateLimit.enable = false;

    # MCP Broker configuration for ZAI Coding Plan Max
    # These match the coding-helper configuration for Claude Code and OpenCode
    # MCP Endpoint: https://api.z.ai/api/mcp/... (glm_coding_plan_global)
    # Note: ZAI has separate endpoints for chat API vs MCP servers
    mcp = {
      enable = true;
      servers = {
        # Web Search MCP - included in Coding Plan Max
        web-search-prime = {
          url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
          headers = {
            Authorization = "Bearer /run/agenix/zai-api-key";
          };
        };
        # Web Reader MCP - included in Coding Plan Max
        web-reader = {
          url = "https://api.z.ai/api/mcp/web_reader/mcp";
          headers = {
            Authorization = "Bearer /run/agenix/zai-api-key";
          };
        };
        # Zread MCP - included in Coding Plan Max
        zread = {
          url = "https://api.z.ai/api/mcp/zread/mcp";
          headers = {
            Authorization = "Bearer /run/agenix/zai-api-key";
          };
        };
        # Vision/Image analysis - available via @z_ai/mcp-server (stdio)
        # ZAI Coding Plan Max includes Vision Understanding
        "4-5v-mcp-server" = {
          url = "https://api.z.ai/api/mcp/4_5v/mcp";
          headers = {
            Authorization = "Bearer /run/agenix/zai-api-key";
          };
        };

        # ========================================================================
        # LOCAL MCP SERVERS (stdio-based)
        # TEMPORARILY DISABLED: Module structure needs investigation
        # ========================================================================

        # # Filesystem MCP server - safe file access to NixOS configuration
        # filesystem = {
        #   type = "local";
        #   command = "npx -y @modelcontextprotocol/server-filesystem /etc/nixos";
        # };

        # # NixOS MCP server - real-time NixOS package data (prevents hallucinations)
        # nixos = {
        #   type = "local";
        #   command = "nix run --extra-experimental-features 'nix-command flakes' github:utensils/mcp-nixos --";
        # };

        # # Git MCP server - version control for NixOS configurations
        # git = {
        #   type = "local";
        #   command = "npx -y @modelcontextprotocol/server-git /etc/nixos";
        # };
      };
    };

    # RAG configuration
    rag = {
      enable = true;
      qdrant.enable = true; # Enable Qdrant service
      qdrant.memoryLimit = "4G";
    };
  };

  # ============================================================================
  # MINING - GPU Mining (RTX 3090)
  # DISABLED: Mining conflicts with AI inference services (LM Studio)
  # Re-enable when AI services are not in use
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
    autostart = false; # Manual control via systemctl
    devices = "1"; # RTX 3090 only (GPU 1) - 3060 Ti disabled for gaming
    powerLimit = 250; # Power limit for RTX 3090 (250W recommended for efficiency)
    apiPort = 4068;
  };

  # XMRig CPU mining (16 threads)
  services.mining.xmrig = {
    enable = true;
    autostart = false; # Manual control via systemctl
    threads = 16;
  };

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
  # Mining metrics exporter (XMRig + lolMiner)
  services.mining-exporter.enable = true;

  # Prometheus server - central metrics collection
  services.monitoring.prometheus.enable = true;
  services.monitoring.prometheus.retentionDays = 30;
  services.monitoring.prometheus.scrapeInterval = "15s";

  # Grafana dashboards
  services.monitoring.grafana.enable = true;

  # TP-Link Switch Orchestration
  # networking.switch-orchestration = {
  #   enable = true;
  #   credentials.username = "admin";
  #   credentials.passwordFile = "/run/agenix/switch-admin";
  # };

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
    slirp4netns # Required for Spacebot/Podman networking
    podman-compose # Docker Compose compatibility for Podman
    (pkgs.writeShellScriptBin "spacebot" ''
      #!${pkgs.bash}/bin/bash
      # Spacebot CLI wrapper - connects to local Spacebot service
      exec ${pkgs.curl}/bin/curl --data-binary @- http://127.0.0.1:19898/api/run "$@"
    '')

    # Hardware monitoring & fan control helpers
    (pkgs.writeShellScriptBin "fan-set" ''
      #!${pkgs.bash}/bin/bash
      # Set fan speed (0-255) for a specific fan
      # Usage: fan-set <fan_number> <pwm_value>
      # Example: fan-set 1 128 (sets fan 1 to 50%)
      if [ "$#" -ne 2 ]; then
        echo "Usage: fan-set <fan_number> <pwm_value (0-255)>"
        echo "Example: fan-set 1 128  # Set fan 1 to 50%"
        exit 1
      fi
      fan=$1
      pwm=$2
      pwm_file="/sys/class/hwmon/hwmon6/pwm$fan"
      if [ ! -w "$pwm_file" ]; then
        echo "Error: Cannot write to $pwm_file"
        echo "You may need to disable BIOS fan control first"
        exit 1
      fi
      echo "$pwm" > "$pwm_file"
      echo "Set fan $fan to PWM $pwm ($(awk "BEGIN {printf \"%.0f\", $pwm/255*100}")%)"
    '')

    (pkgs.writeShellScriptBin "fan-get" ''
      #!${pkgs.bash}/bin/bash
      # Get current fan speed and PWM for all fans
      echo "Fan Status for MSI X570 TOMAHAWK:"
      echo "────────────────────────────────────────"
      for i in 1 2 3 4 5 6 7; do
        pwm_file="/sys/class/hwmon/hwmon6/pwm''$i"
        rpm_file="/sys/class/hwmon/hwmon6/fan''${i}_input"
        label_file="/sys/class/hwmon/hwmon6/fan''${i}_label"
        if [ -f "$pwm_file" ]; then
          pwm=$(cat "$pwm_file" 2>/dev/null || echo "N/A")
          rpm=$(cat "$rpm_file" 2>/dev/null || echo "0")
          label="Fan ''$i"
          [ -f "$label_file" ] && label=$(cat "$label_file")
          percent=$(awk "BEGIN {printf \"%.0f\", $pwm/255*100}")
          printf "%-12s: %4d RPM  PWM: %3d (%3s%%)\n" "$label" "$rpm" "$pwm" "$percent"
        fi
      done
    '')

    (pkgs.writeShellScriptBin "temp-get" ''
      #!${pkgs.bash}/bin/bash
      # Get all temperature readings
      echo "Temperature Readings:"
      echo "────────────────────"
      # AMD CPU temps
      echo "AMD CPU (k10temp):"
      ${pkgs.lm_sensors}/bin/sensors -j k10temp-pci-00c3 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors k10temp-pci-00c3
      echo ""
      # Motherboard temps
      echo "Motherboard (NCT6775):"
      ${pkgs.lm_sensors}/bin/sensors -j nct6797-isa-0a20 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("temp")) | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors nct6797-isa-0a20 | grep -E "SYSTIN|CPUTIN|TSI"
      echo ""
      # NVMe temps
      echo "NVMe Drives:"
      ${pkgs.lm_sensors}/bin/sensors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("nvme")) | "  \(.key): \(.value[\"Composite\"].value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors | grep -A2 nvme
    '')

    # Network discovery & mapping
    nmap
    netdiscover
    arp-scan
    iproute2 # ip, ss, route commands
    iputils # ping, traceroute
    dnsutils # dig, nslookup
    whois
    net-tools # arp, ifconfig, route

    # Development
    nodejs
    gh
    jq
    inputs.claude-native.packages.x86_64-linux.claude

    # AI & ML
    llama-cpp
    whisper-cpp
    pipx
    pkgs.python312Packages.huggingface-hub # HF CLI: hf download/upload/login

    # Mining (manual only, no auto-start)
    xmrig
    lolminer

    # Desktop
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
  ];

  # ============================================================================
  # MULTI-GPU ENVIRONMENT VARIABLES - RTX 3090 + 3060 Ti
  # ============================================================================
  environment.sessionVariables = {
    # GPU visibility
    CUDA_VISIBLE_DEVICES = "0,1";

    # NCCL (NVIDIA Collective Communications Library) settings
    NCCL_P2P_LEVEL = "2"; # PCIe bridge level (P2P limited on heterogeneous GPUs)
    NCCL_P2P_DISABLE = "0"; # Try P2P first, disable if issues occur
    NCCL_IB_DISABLE = "1"; # Disable InfiniBand (not applicable)
    NCCL_ALGO = "Tree"; # Tree algorithm for multi-GPU communication

    # llama.cpp/llama-cpp CUDA settings
    GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1"; # Critical for heterogeneous GPU support
    GGML_CUDA_GPU_MEMORY_FRACTION = "0.9"; # Use 90% of GPU VRAM (leave headroom)
    LLAMA_GRAPH_POOL_SIZE = "0.2"; # CUDA Graphs pool (20% of VRAM)
    # KV cache quantization (Q4_0) is configured per-model in LM Studio GUI
  };

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

        # systemd user environment for secrets (available in all shells)
        systemd.user.sessionVariables = {
          HF_TOKEN = "/run/agenix/huggingface-token";
        };

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

          # Base Vencord/Vesktop settings (plugins, themes, etc.)
          vesktopConfig = {
            # Disable Vencord-side tray settings (managed in writable ~/.config/vesktop/settings.json)
            tray = false;
            trayIcon = false;
            openHidden = false;

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

          # Note: Tray settings (minimizeToTray, trayIcon, etc.) are managed in
          # ~/.config/vesktop/settings.json (writable), not here. Only plugins
          # and Vencord settings are managed declaratively via nixcord.
        };

        # Autostart Vesktop on login with X11 backend for tray icon support
        # Note: nixcord manages plugins and settings declaratively - no additional service needed
        systemd.user.services.vesktop-autostart = {
          Unit = {
            Description = "Vesktop autostart";
            After = [
              "graphical-session-pre.target"
              "plasma-plasmashell.service"
            ];
            PartOf = [ "graphical-session.target" ];
            Wants = [ "plasma-plasmashell.service" ]; # Ensure plasma tray is ready
          };
          Service = {
            Type = "simple";
            Environment = [
              # Force X11 backend for StatusNotifierItem/tray icon support
              # This is required for KDE Plasma 6 on Wayland
              "XDG_CURRENT_DESKTOP=KDE"
              "ELECTRON_OZONE_PLATFORM_HINT=x11"
            ];
            # Use XWayland for proper tray icon support on Wayland
            # --enable-features=UseOzonePlatform --ozone-platform-hint=x11 enables StatusNotifierItem
            # --start-minimized: tray settings are in ~/.config/vesktop/settings.json (writable)
            ExecStart = "${pkgs.vesktop}/bin/vesktop --enable-speech-dispatcher --enable-features=UseOzonePlatform --ozone-platform-hint=x11 --start-minimized";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
      };
  };

  # ============================================================================
  # FIREWALL
  # ============================================================================
  # Note: Many ports are declared here for clarity. Some modules also declare
  # their own firewall ports (e.g., ai-inference, gpu-exporters).
  #
  # Port Reference:
  # - 9757/9758/9759/9947: WiVRn (VR streaming for Quest Pro)
  # - 18789/18790: Steam Remote Play
  # - 19898: Moonlight (NVIDIA GameStream)
  # - 27031/27036: Steam network ports
  # - 5353: mDNS (service discovery)
  #
  # AI Inference ports (auto-configured by modules):
  # - 8080: AI inference gateway (ai-inference module)
  # - 9190: AI inference metrics (ai-inference module)
  # - 9400: NVIDIA GPU exporter (gpu-exporters module)
  networking.firewall = {
    allowedTCPPorts = [
      9757 # WiVRn main port
      18789 # Steam Remote Play
      18790 # Steam Remote Play (secondary)
      19898 # Moonlight/GameStream AND Spacebot Web UI
      1234 # LM Studio API server
      8080 # AI Inference Gateway
    ];
    allowedUDPPorts = [
      9757 # WiVRn
      9758 # WiVRn
      9759 # WiVRn
      27031 # Steam UDP
      27036 # Steam UDP
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
