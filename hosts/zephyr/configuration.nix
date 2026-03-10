# Zephyr Host Configuration
# RTX 3090, Quest Pro, 4K HDR TV
{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # ========================================================================
    # BASE MODULES
    # ========================================================================

    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix
    # Kubernetes module (for control plane)
    ../../modules/services/kubernetes.nix

    # All other modules auto-imported via ../../modules/default.nix
    # This includes: system, desktop, shell, gaming, development, services,
    # plus zephyr-specific modules (nvidia-common, gstreamer, spotify, cluster networking)
    ../../modules/default.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking = {
    hostName = "zephyr";
    networkmanager = {
      enable = true;
      dns = "none";
    };

    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };

    wireless.enable = true;

    firewall = {
      allowedTCPPorts = [
        9757 # WiVRn main port
        18789 # Steam Remote Play
        18790 # Steam Remote Play (secondary)
        19898 # Moonlight/GameStream AND Spacebot Web UI
        1234 # LM Studio API server
        8080 # AI Inference Gateway
        53317 # LocalSend (file sharing)
        8888 # CFSSL CA API server (for worker node certificate generation)
      ];
      allowedUDPPorts = [
        9757 # WiVRn
        9758 # WiVRn
        9759 # WiVRn
        27031 # Steam UDP
        27036 # Steam UDP
        5353 # mDNS
        9947 # WiVRn
        53317 # LocalSend (multicast discovery)
      ];
      interfaces = {
        "tailscale0".allowedTCPPorts = [
          18789
          18790
        ];
        # NFS server - allow local network only
        "enp38s0".allowedTCPPorts = [
          111
          2049
          20048
        ]; # rpcbind, nfs, mountd
        "enp38s0".allowedUDPPorts = [
          111
          2049
          20048
        ];
      };
    };
  };

  # ============================================================================
  # SECURITY AUDIT REMEDIATION
  # ============================================================================
  # Enables firewall, Tailscale SSH, and service hardening
  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  hardware = {
    profiles = {
      amd.zen = true; # Zen CPU optimizations (kernel params)
      nvidia.enable = true; # NVIDIA GPU support
      nvidia.multiGpu = true; # Multi-GPU (RTX 3090 + 3060 Ti)
      corsair.enable = true; # Corsair AIO + RGB
      monitoring.enable = true; # Hardware monitoring
    };

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = false; # Skip auto-detect, we know the hardware
      fanControl = true; # Custom fan curve control
    };

    # Corsair extras (not covered by profile)
    corsair = {
      aio.enable = true; # Corsair H115i AIO control
      rgb.enable = true; # OpenRGB for RGB control
      autoStartRgb = false; # Don't auto-start (conflicts with liquidctl)
    };

    # Bluetooth support via BlueZ
    bluetooth.enable = true;
  };

  # ============================================================================
  # WIRELESS HARDWARE
  # ============================================================================

  # Timezone and locale
  time.timeZone = "America/Winnipeg";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Bootloader
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Use latest kernel
    kernelPackages = pkgs.linuxPackages_zen;

    # Multi-GPU kernel modules for RTX 3090 + 3060 Ti
    # (Note: hardware.profiles.nvidia.enable adds nvidia modules automatically)
    kernelModules = [
      "nvidia_uvm" # Unified Memory (CRITICAL for multi-GPU!)
    ];

    # Zephyr-specific kernel params for gaming
    # (Note: hardware.profiles.amd.zen adds split_lock_detect, threadirqs, preempt)
    kernelParams = [
      "processor.max_cstate=1"
      "intel_idle.max_cstate=1"
      "iommu=pt"
    ];
  };

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  profiles.role = {
    workstation = true; # Desktop + development
    gaming = true; # Steam, Lutris, etc.
    vr = true; # WiVRn for Quest Pro
    mining = true; # GPU/CPU mining
    aiInference = true; # AI inference gateway + MCP + RAG
  };

  # Note: profiles.role.gaming enables services.gaming automatically
  # NOTE: Distributed builds configured in modules/system/distributed-builds.nix
  # Do not override here to avoid conflicts

  # ============================================================================
  # SERVICES - Consolidated service configuration
  # ============================================================================
  services = {
    # Kubernetes control plane + worker role on Zephyr
    kubernetes-module = {
      enable = true;
      masterAddress = "10.1.1.110"; # Zephyr's IP
      roles = ["master" "node"];
    };

    # DNS - Use local unbound resolver for cluster hostnames
    unbound-cluster = {
      enable = true;
    };

    # Gaming HDR for 4K HDR TV
    gaming.hdr.enable = true;

    # Share /etc/nixos via NFS for remote hosts (single-source-of-truth)
    nixos-share = {
      enable = true;
      server.enable = true;
    };

    # Spacebot AI agent (integrated with AI Gateway)
    spacebot = {
      enable = true;
      useGateway = true;
      gatewayUrl = "http://127.0.0.1:8080";
      host = "127.0.0.1";
      port = 19898;
      memory = "4G";
      cpu = "2";
      hideUpdateNotification = true;
      providerKeys = {
        ZAI_CODING_PLAN_KEY = "/run/agenix/zai-api-key";
        KILO_API_KEY = "/run/agenix/kilo-api-key";
      };
      discord.enable = false;
      telegram.enable = true;
      telegram.tokenFile = "/run/agenix/spacebot-telegram-token";
    };

    # Redis - For gateway rate limiting and caching
    redis.servers."".enable = true;

    # AI Inference Service - Gateway with authentication and metrics
    ai-inference = {
      enable = true;
      backend = {
        url = "http://127.0.0.1:1234";
        type = "lm-studio";
        lmStudio.apiKeyFile = "/run/agenix/lm-studio-api-key";
        zai = {
          enable = true;
          apiKeyFile = "/run/agenix/zai-api-key";
          baseUrl = "https://api.z.ai/api/coding/paas/v4";
        };
      };
      gateway = {
        enable = true;
        host = "127.0.0.1";
        port = 8080;
        workers = 1;
      };
      routing = {
        enable = true;
        defaultModel = "qwen3.5-35b-a3b";
        fallbackChain = ["vllm" "lm-studio" "zai"];
      };
      auth.mode = "none";
      monitoring.enable = true;
      rateLimit.enable = false;
      mcp = {
        enable = true;
        servers = {
          web-search-prime = {
            url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
            headers.Authorization = "Bearer /run/agenix/zai-api-key";
          };
          web-reader = {
            url = "https://api.z.ai/api/mcp/web_reader/mcp";
            headers.Authorization = "Bearer /run/agenix/zai-api-key";
          };
          zread = {
            url = "https://api.z.ai/api/mcp/zread/mcp";
            headers.Authorization = "Bearer /run/agenix/zai-api-key";
          };
          "4-5v-mcp-server" = {
            url = "https://api.z.ai/api/mcp/4_5v/mcp";
            headers.Authorization = "Bearer /run/agenix/zai-api-key";
          };
          nix-rebuild = {
            type = "local";
            command = [
              "${(pkgs.python3.withPackages (ps: [ps.mcp])).interpreter}"
              "/etc/nixos/skills/nix-rebuild-mcp/server.py"
            ];
            environment.NIX_HOST = "zephyr";
            enabled = true;
          };
          add-service = {
            type = "local";
            command = [
              "${(pkgs.python3.withPackages (ps: [ps.mcp])).interpreter}"
              "/etc/nixos/skills/add-service-mcp/server.py"
            ];
            environment = {};
            enabled = true;
          };
        };
      };
      rag = {
        enable = true;
        qdrant.enable = true;
        qdrant.memoryLimit = "4G";
      };
    };

    # LM Studio Headless Service (llmster daemon)
    lm-studio-headless = {
      enable = true;
      user = "j_kro";
      port = 1234;
      host = "127.0.0.1";
      gpuDevice = null;
    };

    # MCP Servers for AI tools
    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
    };

    # WEB TESTING - Playwright/Puppeteer system dependencies
    web-testing.enable = true;

    # CI/CD - Self-hosted GitHub Actions runner
    ci-runner = {
      enable = false;
      repo = "username/nixos-config";
      autoStart = false;
    };

    # HOME ASSISTANT - Smart Home Automation Platform
    home-assistant = {
      enable = true;
      openFirewall = true;
      config = {
        homeassistant = {
          name = "Zephyr";
          latitude = "49.8951";
          longitude = "-97.1384";
          temperature_unit = "C";
          time_zone = "America/Winnipeg";
          unit_system = "metric";
        };
      };
    };

    # MULTIMEDIA - GStreamer support for Qt/KDE applications
    multimedia.gstreamer.enable = true;

    # Spotify with SpotX patch (ad-free, premium features)
    spotify-spotx = {
      enable = true;
      forceX11 = true;
      clearCacheOnPatch = true;
    };

    # FLATPAK - Flatpak support with Discover and Flathub
    flatpak-kde = {
      enable = true;
      autoUpdate = true;
    };

    # MINING - GPU Mining (RTX 3090)
    mining.lolminer.nvidia = {
      enable = true;
      autostart = false;
      devices = "1";
      powerLimit = 250;
      apiPort = 4068;
    };
    mining.xmrig = {
      enable = true;
      autostart = false;
      threads = 16;
    };

    # MONITORING - Full monitoring stack
    monitoring = {
      prometheus = {
        enable = true;
        retentionDays = 30;
        scrapeInterval = "15s";
        enableAlertRules = true;
      };
      alertmanager = {
        enable = true;
        retentionDays = 30;
      };
      loki = {
        enable = true;
        retentionPeriod = "30d";
      };
      promtail = {
        enable = true;
        lokiUrl = "http://127.0.0.1:3100";
      };
      grafana.enable = true;
    };

    # GlitchTip error tracking (self-hosted Sentry alternative)
    glitchtip-selfhosted = {
      enable = true;
      host = "127.0.0.1";
      port = 8000;
      openFirewall = false;
      database.passwordFile = "/run/agenix/glitchtip-db-password";
      secretKeyFile = "/run/agenix/glitchtip-secret-key";
      enableForGateway = true;
    };
  };

  # ============================================================================
  # PROGRAMS - SCOPEBUDDY, ANIME GAME LAUNCHERS, AI SERVICES
  # ============================================================================
  programs = {
    scopebuddy = {
      enable = true;
      autoDetect = {
        resolution = true;
        hdr = true;
        vrr = true;
      };
    };

    # Anime game launchers
    anime-game-launcher.enable = true;
    sleepy-launcher.enable = true;
    honkers-railway-launcher.enable = true;
    wavey-launcher.enable = true;

    # AI services
    lm-studio.enable = true;
    stability-matrix.enable = true;
  };

  # Podman container runtime (for Spacebot)
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  # Agenix secrets for AI services
  age = {
    identityPaths = ["/home/j_kro/.age/key.txt"];

    secrets = {
      lm-studio-api-key = {
        file = "${inputs.self}/secrets/lm-studio-api-key.age";
        mode = "440";
        owner = "ai-inference";
        group = "ai-inference";
      };

      huggingface-token = {
        file = "${inputs.self}/secrets/huggingface-token.age";
        mode = "440";
        owner = "j_kro";
        group = "users";
      };

      zai-api-key = {
        file = "${inputs.self}/secrets/zai-api-key.age";
        mode = "440";
        owner = "j_kro";
        group = "ai-inference";
      };

      # Kilo API key - Kilo Code provider for Spacebot
      kilo-api-key = {
        file = "${inputs.self}/secrets/kilo-api-key.age";
        mode = "440";
        owner = "j_kro";
        group = "users";
      };

      # GlitchTip error tracking secrets
      glitchtip-db-password = {
        file = "${inputs.self}/secrets/glitchtip-db-password.age";
        mode = "440";
        owner = "root";
        group = "root";
        symlink = true;
      };

      glitchtip-secret-key = {
        file = "${inputs.self}/secrets/glitchtip-secret-key.age";
        mode = "440";
        owner = "root";
        group = "root";
        symlink = true;
      };

      # XMRig HTTP API token - For pause/resume via API during builds
      xmrig-api-token = {
        file = "${inputs.self}/secrets/xmrig-api-token.age";
        mode = "440";
        owner = "mining";
        group = "mining";
      };

      # Tailscale API key - Tailscale service authentication
      tailscale-api-key = {
        file = "${inputs.self}/secrets/tailscale-api-key.age";
        mode = "440";
        owner = "j_kro";
        group = "users";
      };

      # Spacebot Discord bot token
      # TEMPORARILY DISABLED: Secret file not yet created
      # spacebot-discord-token = {
      #   file = "${inputs.self}/secrets/spacebot-discord-token.age";
      #   mode = "440";
      #   owner = "root";
      #   group = "root";
      # };

      # Spacebot Telegram bot token - TrovesAndCoves client communication
      spacebot-telegram-token = {
        file = "${inputs.self}/secrets/spacebot-telegram-token.age";
        mode = "440";
        owner = "root";
        group = "root";
      };
    };
  };

  # ============================================================================
  # AI INFERENCE SERVICE - Gateway with authentication and metrics
  # Gateway routes to LM Studio backend with API token authentication
  # Backend: LM Studio on port 1234
  # Gateway: OpenAI-compatible API on port 8080
  # ============================================================================

  # ============================================================================
  # WEB TESTING - Playwright/Puppeteer system dependencies
  # Provides GTK libraries and fonts for Chromium-based browsers
  # ============================================================================

  # ============================================================================
  # CI/CD - Self-hosted GitHub Actions runner
  # ============================================================================
  # SETUP REQUIRED (one-time):
  #   sudo /etc/nixos/scripts/ci/setup-runner.sh owner/repo
  # After setup, set enable = true and autoStart = true below

  # ============================================================================
  # MINING - GPU Mining (RTX 3090)
  # DISABLED: Mining conflicts with AI inference services (LM Studio)
  # Re-enable when AI services are not in use
  # ============================================================================
  # Note: profiles.role.mining enables services.mining automatically

  # ============================================================================
  # FLATPAK - Flatpak support with Discover and Flathub
  # ============================================================================

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

  # Systems Intelligence Plasmoid - Cluster monitoring widget
  programs.systems-intelligence-plasmoid.enable = true;
  programs.systems-intelligence-plasmoid.prometheusUrl = "http://127.0.0.1:9090";
  programs.systems-intelligence-plasmoid.refreshInterval = 5000;
  programs.systems-intelligence-plasmoid.clusterNodes = "zephyr,nexus,forge,sentry";

  # ============================================================================
  # MONITORING - Full monitoring stack
  # ============================================================================

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  profiles.network.tailscale.enable = true;

  # ============================================================================
  # ADDITIONAL PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # Shell & CLI
    fish
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
    localsend # Local network file sharing (AirDrop alternative)

    # Deployment
    inputs.colmena.packages.${system}.colmena
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

    (pkgs.writeShellScriptBin "sys-mon" ''
      #!${pkgs.bash}/bin/bash
      # Comprehensive system monitoring dashboard
      exec /etc/nixos/scripts/monitor-sensors.sh
    '')

    (pkgs.writeShellScriptBin "aio-status" ''
      #!${pkgs.bash}/bin/bash
      # Corsair AIO cooler status
      exec /etc/nixos/scripts/corsair-status.sh
    '')

    (pkgs.writeShellScriptBin "corsair-rgb" ''
      #!${pkgs.bash}/bin/bash
      # Start OpenRGB GUI for Corsair RGB control
      exec /etc/nixos/scripts/corsair-rgb
    '')

    (pkgs.writeShellScriptBin "corsair-rgb-server" ''
      #!${pkgs.bash}/bin/bash
      # Start OpenRGB server for programmatic RGB control
      exec /etc/nixos/scripts/corsair-rgb-server
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
    users.j_kro = {pkgs, ...}: {
      imports = [
        inputs.zen-browser.homeModules.twilight
        inputs.nixcord.homeModules.nixcord
        ../../modules/home-manager/fish.nix
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

        # PWA Support - enables installing websites as native applications
        nativeMessagingHosts = [pkgs.firefoxpwa];

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

            // Dark mode - signal to websites that system prefers dark mode
            // This enables native dark themes on supporting websites via CSS prefers-color-scheme
            user_pref("ui.systemUsesDarkTheme", 1);
            user_pref("browser.in-content.dark-mode", true);
            user_pref("layout.css.prefers-color-scheme.content-override", 2); // 2 = dark

            // Performance optimizations
            user_pref("gfx.webrender.all", true);
            user_pref("media.ffmpeg.vaapi.enabled", true);
            // NOTE: Disabled widget.dmabuf.force-enabled for NVIDIA + Wayland compatibility
            // Forced DMA-BUF causes image corruption in WebGL/Canvas applications (e.g., Facebook Messenger)
            // Browser will auto-detect appropriate buffer mechanism per-GPU
            // user_pref("widget.dmabuf.force-enabled", true);

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
                urls = [{template = "https://www.google.com/search?q={searchTerms}";}];
                icon = "https://www.google.com/favicon.ico";
                definedAliases = [
                  "@g"
                  "@google"
                ];
              };
              ddg = {
                urls = [{template = "https://duckduckgo.com/?q={searchTerms}";}];
                icon = "https://duckduckgo.com/favicon.ico";
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
          PartOf = ["graphical-session.target"];
          Wants = ["plasma-plasmashell.service"]; # Ensure plasma tray is ready
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
          WantedBy = ["graphical-session.target"];
        };
      };
    };
  };

  # ============================================================================
  # SYSTEM STATE
  # ============================================================================
  system.stateVersion = "26.05";
}
