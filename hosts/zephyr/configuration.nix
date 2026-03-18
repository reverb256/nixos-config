# Zephyr Host Configuration
# RTX 3090, Quest Pro, 4K HDR TV
{
  pkgs,
  lib,
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
    # Kubernetes module (for control plane)
    ../../modules/services/kubernetes.nix
    # Keepalived VIP for Kubernetes HA
    ../../modules/services/keepalived-vip.nix
    # Akash Provider - Earn AKT/USDC from GPU compute
    ../../modules/services/akash-provider.nix

    # All other modules auto-imported via ../../modules/default.nix
    # This includes: system, desktop, shell, gaming, development, services,
    # plus zephyr-specific modules (nvidia-common, gstreamer, spotify, cluster networking)
    ../../modules/default.nix

    # RGB control for peripherals and components
    ../../modules/hardware/rgb-control.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  # Note: interfaceName provided by node-profiles.zephyr-workstation
  clusterNetworking = {
    enable = true;
    hostName = "zephyr";
    ipAddress = "10.1.1.110";
    wireless.enable = true; # WiFi interface: wlo1 (native: wlp40s0)
    unbound.listenAddress = "10.1.1.110"; # Listen on node IP for cluster DNS
  };

  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };
    # Zephyr-specific firewall rules (in addition to cluster defaults)
    firewall = {
      allowedTCPPorts = [
        9757 # WiVRn main port
        18789 # Steam Remote Play
        18790 # Steam Remote Play (secondary)
        19898 # Moonlight/GameStream AND Spacebot Web UI
        1234 # LM Studio API server
        3333 # XMRig stratum proxy (for GPU miners)
        8080 # AI Inference Gateway
        8083 # Llamafile standalone LLM service
        53317 # LocalSend (file sharing)
        8888 # CFSSL CA API server (for worker node certificate generation)
        3900 # Garage S3 API
        3901 # Garage RPC
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
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  profiles.node.zephyr-workstation.enable = true;

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
  # GPU COMPUTE - CUDA + Vulkan support for AI inference
  # ============================================================================
  hardware.gpu-compute = {
    enable = true;
    cuda.enable = true; # CUDA for NVIDIA RTX 3090 + 3060 Ti
    vulkan.enable = true; # Vulkan as fallback/universal backend
  };

  # ============================================================================
  # SERVICES - All service configurations consolidated here
  # ============================================================================
  services = {
    # KUBERNETES HA - Control Plane Configuration
    # Override profile defaults for HA setup with etcd clustering and VIP
    kubernetes-module = {
      # Use VIP (10.1.1.100) for HA control plane - certificates now include VIP and all node IPs in SANs
      # If zephyr (highest priority) fails, nexus or sentry takes over the VIP automatically
      masterAddress = lib.mkForce "10.1.1.100";
      # etcd clustering configuration (3-node HA cluster operational)
      etcdInitialState = "existing"; # Cluster already formed
      etcdName = "zephyr";
      etcdListenHost = "10.1.1.110";
      # etcdBootstrapOnly removed - multi-node cluster is operational
      # All 3 cluster members
      etcdClusterMembers = [
        "zephyr=http://10.1.1.110:2380"
        "nexus=http://10.1.1.120:2380"
        "sentry=http://10.1.1.140:2380"
      ];
    };

    # Keepalived VIP - priority 110 (highest - preferred master)
    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "enp38s0";
      priority = 110;
    };

    # AKASH PROVIDER - Decentralized GPU Compute Marketplace
    # Earn AKT/USDC by hosting AI/ML workloads on your GPUs
    akash-provider = {
      enable = true; # Wallet created with agenix, ready to deploy
      # Provider address: cluster-provider (created 2026-03-14)
      providerAddress = "akash1s97zjxzn3tnudawjhjhpus9x7yn6dgukzar372";
      # Domain for provider ingress (using Quick Tunnel for testing)
      # WARNING: Quick Tunnel URLs change on restart - use own domain for production
      domain = "provider.reverb256.ca";
      clusterPublicHostname = "provider.reverb256.ca";

      # GPU pricing (uakt per block) - adjust based on market demand
      pricing = {
        rtx3090 = 20000; # ~$8.70/month per GPU at 50% util
        rtx4060 = 18000; # ~$7.80/month per GPU at 50% util
        rtx3060ti = 15000; # ~$6.50/month per GPU at 50% util
        # rx5700xt = 8000; # AMD GPU not supported by akash-provider module
        # rx5600xt = 7000; # AMD GPU not supported by akash-provider module
      };
    };

    # Cloudflare Tunnel - Akash provider ingress
    cloudflared-tunnel = {
      enable = true;
      tunnelId = "2face449-f837-4fb1-87c5-a5a11c17e9ae";
      ingressRules = [
        # Provider bid engine
        {
          hostname = "provider.reverb256.ca";
          service = "http://localhost:8443";
        }
        # Tenant ingress (wildcard for deployments)
        {
          hostname = "*.ingress.reverb256.ca";
          service = "http://localhost:80";
        }
        # Fallback for bare ingress domain
        {
          hostname = "ingress.reverb256.ca";
          service = "http://localhost:80";
        }
      ];
    };

    # Crash watchdog - detect and log system crashes
    crash-watchdog.enable = true;

    # Backup to Garage S3 - automated daily backups
    backup-to-garage = {
      enable = true;
      endpoint = "http://10.1.1.110:3900";
      region = "garage";
      bucket = "backups";
      accessKey = "GKac91d924fc76a30b9bcf6c3e";
      secretKeyFile = "/run/agenix/garage-s3-secret-key";
      retentionDays = 30;
      startAt = "02:00"; # 2 AM daily
    };
  };

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  # Base profiles provided by node-profiles.zephyr-workstation:
  # - amd.zen, nvidia.enable, nvidia.multiGpu, monitoring.enable
  #
  # Zephyr-specific hardware overrides/additions:
  hardware = {
    profiles = {
      corsair.enable = true; # Corsair AIO + RGB (not in node profile)
    };

    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

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

    # RGB control for peripherals and components
    rgb-control = {
      enable = true;
      openrgb.enable = true; # Motherboard, GPU, Corsair devices
      openrazer.enable = true; # Razer Naga Pro mouse
      temperatureReactive = {
        enable = true;
        sensor = "both"; # Monitor both CPU and GPU temps
        thresholds = {
          cool = 50;
          warm = 65;
          hot = 75;
        };
        interval = 5;
      };
    };

    # Bluetooth support via BlueZ
    bluetooth.enable = true;
  };

  # ============================================================================
  # FILESYSTEM COMPRESSION - Enable zstd on all BTRFS filesystems
  # ============================================================================
  # Root and home filesystems lack compression in hardware-configuration.nix
  # Use mkOptionDefault to add compression without breaking other options
  fileSystems = {
    "/".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
    ];
    "/home".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
    ];
  };

  # ============================================================================
  # WIRELESS HARDWARE
  # ============================================================================

  # Locale (timezone inherits cluster default: UTC)
  i18n.defaultLocale = "en_CA.UTF-8";

  # ============================================================================
  # BOOT CONFIGURATION
  # ============================================================================
  # Base bootloader settings provided by common-host-defaults.nix:
  # - systemd-boot.enable, efi.canTouchEfiVariables, kernelPackages (linux_zen)
  #
  # Zephyr-specific additions:
  boot = {
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
  # Base role profiles provided by node-profiles.zephyr-workstation:
  # - workstation, gaming, vr, mining, aiInference
  # Kubernetes and networking also handled by node profile
  #
  # No additional role profiles needed - all handled by node profile

  # Note: profiles.role.gaming enables services.gaming automatically
  # NOTE: Distributed builds configured in modules/system/distributed-builds.nix
  # Do not override here to avoid conflicts

  # ============================================================================
  # SERVICES - Consolidated service configuration
  # ============================================================================
  # Base Kubernetes configuration provided by node-profiles.zephyr-workstation
  # (master + node roles, masterAddress, etc.)
  #
  # Zephyr-specific service additions:
  services = {
    # Compute Workload Monitor - Use conservative profile for memory-constrained system
    # Zephyr has 31GB RAM and runs AI workloads - earlier intervention needed
    compute-workload-monitor = {
      enable = true;
      profile = "conservative"; # Lower PSI thresholds for earlier build/mining pause
    };

    # NIX BINARY CACHE - Serve pre-built packages to cluster
    # Eliminates redundant builds across nodes, speeds up deployments
    binary-cache = {
      enable = true;
      port = 50000;
      bindAddress = "10.1.1.110";
    };

    # GPU Resource Marketplace - Unified auction engine for GPU allocation
    # Coordinates between mining, Kubernetes, Akash, and gaming workloads
    compute-market = {
      enable = true;
      auctionInterval = 30; # Run auction every 30 seconds

      # Bidders configuration
      bidders = {
        # Mining bidder configuration
        mining = {
          enable = true;
          hourlyRevenue = 0.10; # $0.10/hr per GPU (baseline bid)
          services = [
            "lolminer-nvidia"
            "xmrig"
          ];
        };

        # Kubernetes bidder configuration
        kubernetes = {
          enable = true;
          baseBid = 2.50; # $2.50/hr base bid for K8s workloads
          urgencyMultiplier = 2.0; # 2x multiplier for urgent jobs
          namespace = "default";
        };

        # Akash bidder configuration
        akash = {
          enable = true;
          profitMargin = 0.90; # Bid 90% of market rate (10% buffer)
          namespace = "akash-services";
        };

        # Gaming override (always wins)
        gaming = {
          enable = true;
          processes = [
            "steam"
            "steamwebhelper"
            "steamapps"
            "lutris"
            "heroic"
            "Lutris"
            "HeroicGamesLauncher"
            "wine"
            "proton"
          ];
        };
      };

      # Prometheus metrics
      prometheus = {
        enable = true;
        port = 9200;
      };
    };

    # Gaming HDR for 4K HDR TV
    gaming.hdr.enable = true;

    # XMRig Proxy - Centralized stratum proxy for CPU (RandomX) and GPU (CR29) mining
    xmrig-proxy = {
      enable = true;

      config = builtins.toJSON {
        pools = [
          # CPU Mining Pools (RandomX)
          {
            id = "kryptex-rx-primary";
            algo = "rx/0";
            url = "xtm-rx-us.kryptex.network:8038";
            user = "krxXVNVMM7.cpu-proxy";
            pass = "x";
            tls = true;
            keepalive = true;
            priority = 1;
          }
          {
            id = "kryptex-rx-eu";
            algo = "rx/0";
            url = "xtm-rx-eu.kryptex.network:8038";
            user = "krxXVNVMM7.cpu-proxy";
            pass = "x";
            tls = true;
            keepalive = true;
            priority = 2;
          }
          # GPU Mining Pools (Cuckaroo29/CR29)
          {
            id = "kryptex-cr29-us";
            algo = "cn/cc29";
            url = "xtm-c29-us.kryptex.network:8040";
            user = "krxXVNVMM7.gpu-proxy";
            pass = "x";
            tls = true;
            keepalive = true;
            priority = 1;
          }
          {
            id = "kryptex-cr29-eu";
            algo = "cn/cc29";
            url = "xtm-c29-eu.kryptex.network:8040";
            user = "krxXVNVMM7.gpu-proxy";
            pass = "x";
            tls = true;
            keepalive = true;
            priority = 2;
          }
        ];

        workers = [
          # CPU Workers
          {
            id = "zephyr-cpu";
            password = "x";
          }
          {
            id = "nexus-cpu";
            password = "x";
          }
          {
            id = "sentry-cpu";
            password = "x";
          }
          # GPU Workers
          {
            id = "zephyr-gpu";
            password = "x";
          }
          {
            id = "nexus-gpu";
            password = "x";
          }
          {
            id = "forge-gpu";
            password = "x";
          }
        ];

        api = {
          port = 8081;
          restricted = true;
          tokenFile = "/run/agenix/xmrig-api-token";
        };

        log = {
          level = 5;
        };
      };
    };

    # Share /etc/nixos via NFS for remote hosts (single-source-of-truth)
    nixos-share = {
      enable = true;
      server.enable = true;
    };

    # NFS Client - Mount shared storage from nexus
    # TEMPORARILY DISABLED: NFS server on Nexus is down, causing hangs/crashes
    nfs-client = {
      enable = true;
      mountShared = false; # DISABLED until Nexus NFS server is fixed
      mountHome = false; # Zephyr has local home
      mountMedia = false; # DISABLED until Nexus NFS server is fixed
    };

    # Caddy reverse proxy - Replace nginx for all services
    caddy = {
      enable = true;
      # Custom Caddyfile for complex configurations (Nextcloud)
      configFile = pkgs.writeText "Caddyfile" ''
        # SearXNG privacy-friendly search (via Tailscale)
        search.zephyr.tigris-ule.ts.net:9001 {
          reverse_proxy 127.0.0.1:7777
        }

        # AI Inference Gateway (via Tailscale)
        ai.zephyr.tigris-ule.ts.net:9002 {
          reverse_proxy 127.0.0.1:8080
        }

        # Host Dashboard (LAN access - no TLS)
        http://zephyr.lan {
          reverse_proxy 127.0.0.1:8090
        }
        http://dashboard.zephyr.lan {
          reverse_proxy 127.0.0.1:8090
        }
      '';
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

    # SearXNG - Privacy-respecting metasearch engine for AI gateway
    searxng.enable = true;

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
        pollinations = {
          enable = true;
          apiKeyFile = "/run/agenix/pollinations-api-key";
          baseUrl = "https://text.pollinations.ai";
        };
      };
      gateway = {
        enable = true;
        host = "127.0.0.1";
        port = 8080;
        workers = 1;
        middleware.redis.enable = true;
      };
      routing = {
        enable = true;
        defaultModel = "qwen3.5-35b-a3b";
        fallbackChain = [
          "vllm"
          "lm-studio"
          "zai"
        ];
      };
      auth.mode = "none";
      monitoring.enable = true;
      rateLimit.enable = false;
      mcp = {
        enable = true;
        servers = {
          nix-rebuild = {
            type = "local";
            command = [
              "${(pkgs.python3.withPackages (ps: [ ps.mcp ])).interpreter}"
              "/etc/nixos/skills/nix-rebuild-mcp/server.py"
            ];
            environment.NIX_HOST = "zephyr";
            environment.NIX_ACCEPT_FLAKE_CONFIG = "1";
            enabled = true;
          };
          add-service = {
            type = "local";
            command = [
              "${(pkgs.python3.withPackages (ps: [ ps.mcp ])).interpreter}"
              "/etc/nixos/skills/add-service-mcp/server.py"
            ];
            environment = { };
            enabled = true;
          };
          context7 = {
            type = "local";
            command = [ "mcp-context7" ];
            environment.CONTEXT7_API_KEY_FILE = "/run/agenix/context7-api-key";
            enabled = true;
          };
          # SearXNG local MCP server - privacy-respecting metasearch
          searxng = {
            type = "local";
            command = [
              "python3"
              "-m"
              "ai_inference_gateway.mcp_servers.searxng_server"
            ];
            environment = {
              SEARXNG_URL = "http://127.0.0.1:7777";
              SEARXNG_CACHE_TTL = "300";
            };
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
      servers.context7.apiKeyFile = "/run/agenix/context7-api-key";
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

    # MINING - GPU Mining (RTX 3090 + RTX 3060 Ti)
    # Direct Kryptex connection (no gpu-proxy - was causing issues)
    mining = {
      lolminer = {
        pool = "stratum+tcp://127.0.0.1:3333"; # Local stratum proxy
        wallet = "krxXVNVMM7.zephyr-gpu";
        pools = [
          {
            url = "stratum+tcp://127.0.0.1:3333"; # Local stratum proxy
            wallet = "krxXVNVMM7.zephyr-gpu";
            password = "x";
            tls = true;
          }
          {
            url = "xtm-c29-us.kryptex.network:8040"; # Direct Kryptex US (fallback)
            wallet = "krxXVNVMM7.zephyr-gpu";
            password = "x";
            tls = true; # TLS required for Kryptex
          }
          {
            url = "xtm-c29-eu.kryptex.network:8040"; # Direct Kryptex EU (fallback)
            wallet = "krxXVNVMM7.zephyr-gpu";
            password = "x";
            tls = true; # TLS required for Kryptex
          }
        ];
      };
      # NVIDIA GPU mining with per-GPU power limits
      # Device 1: RTX 3090 @ 250W (VRAM-safe) - 3060 Ti disabled
      lolminer.nvidia = {
        enable = true;
        autostart = true;
        devices = "1";
        perGpuPowerLimits = [ 250 ]; # [3090] - 3060 Ti disabled
        apiPort = 4068;
      };
      # CPU mining - Dual XMRig setup (always-on + pause-able)
      # Total when idle: 16 threads (50%) - Total when gaming: 4 threads (12%)
      xmrigDual = {
        enable = true;
        # Always-on instance - mines even during gaming
        alwaysOn = {
          enable = true;
          threads = 4; # 12% of 32 cores - unintrusive during gaming
          httpPort = 8081;
          httpTokenFile = "/run/agenix/xmrig-always-api-token";
          autostart = true;
        };
        # Flexible instance - pauses during gaming/builds
        flexible = {
          enable = true;
          threads = 12; # 38% of 32 cores - extra capacity when idle
          httpPort = 8082;
          httpTokenFile = "/run/agenix/xmrig-flexible-api-token";
          autostart = true;
        };
        # Common settings for both instances
        pool = "10.1.1.110:3333"; # Point to local proxy
        wallet = "zephyr-cpu"; # Worker ID for proxy
        password = "x";
        tls = false; # Disable TLS for local proxy connection
      };
    };

    # MONITORED - Full monitoring stack
    # Note: Loki and Promtail moved to monitoring.nix (Loki now on Sentry)
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

    # Vaultwarden - Self-hosted password manager with FIDO2/WebAuthn
    vaultwarden-module = {
      enable = true;
      hostName = "vaultwarden.zephyr.tigris-ule.ts.net"; # Tailscale Magic DNS
      dataDir = "/var/lib/vaultwarden";
    };

    # Syncthing P2P file sync for /etc/nixos config sync
    syncthing-cluster = {
      enable = true;
      deviceId = "ZEPHYR-PLACEHOLDER";
    };

    # Garage S3 disabled - using nexus as primary storage node
    # Access Garage S3 at: http://10.1.1.120:3900
    garage-cluster.enable = false;

    # Host Dashboard - Web interface for cluster host status
    host-dashboard = {
      enable = true;
      role = "control-plane + ai-workstation";
      port = 8090;
      prometheusUrl = "http://127.0.0.1:9090";
      featuredServices = [
        {
          name = "AI Gateway";
          url = "http://127.0.0.1:8080";
        }
        {
          name = "Prometheus";
          url = "http://127.0.0.1:9090";
        }
        {
          name = "Grafana";
          url = "http://127.0.0.1:3000";
        }
        {
          name = "Home Assistant";
          url = "http://127.0.0.1:8123";
        }
      ];
      services = [
        {
          name = "AI Inference Gateway";
          active = true;
        }
        {
          name = "Prometheus";
          active = true;
        }
        {
          name = "Grafana";
          active = true;
        }
        {
          name = "Loki";
          active = true;
        }
        {
          name = "Home Assistant";
          active = true;
        }
        {
          name = "Vaultwarden";
          active = true;
        }
        {
          name = "GlitchTip";
          active = true;
        }
        {
          name = "Garage S3";
          active = true;
        }
        {
          name = "NFS Server";
          active = true;
        }
        {
          name = "XMRig Proxy";
          active = true;
        }
      ];
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

  # ============================================================================
  # AGENIX SECRETS - Centralized registry (2026-03-16 migration)
  # ============================================================================
  # All secrets managed via agenix-secrets-registry module
  # Categories: aiServices, monitoring, storage, mining, cloud, selfHosting
  # See: modules/system/agenix-secrets-registry.nix
  services.agenix-secrets-registry = {
    enable = true;
    aiServices = true;
    monitoring = false; # TODO: Re-enable after creating sentry-dsn.age
    storage = true; # Required for backup-to-garage service (S3 API key)
    mining = true;
    cloud = true;
    selfHosting = false; # These services run on other hosts
  };

  # Override specific secret permissions (registry defaults can be overridden)
  age = {
    identityPaths = [ "/home/j_kro/.age/key.txt" ];
    secrets.xmrig-api-token = lib.mkForce {
      file = "${inputs.self}/secrets/xmrig-api-token.age";
      mode = "440";
      owner = "mining";
      group = "mining";
    };
    secrets.xmrig-always-api-token = lib.mkForce {
      file = "${inputs.self}/secrets/xmrig-always-api-token.age";
      mode = "440";
      owner = "mining";
      group = "mining";
    };
    secrets.xmrig-flexible-api-token = lib.mkForce {
      file = "${inputs.self}/secrets/xmrig-flexible-api-token.age";
      mode = "440";
      owner = "mining";
      group = "mining";
    };
    secrets.akash-provider-key = lib.mkForce {
      file = "${inputs.self}/secrets/akash-provider-key.age";
      mode = "400";
      owner = "root";
      group = "root";
    };
    secrets.cloudflared-token = lib.mkForce {
      file = "${inputs.self}/secrets/cloudflared-token.age";
      mode = "400";
      owner = "root";
      group = "root";
    };
    # Note: spacebot-telegram-token uses registry default (owner=j_kro)
    # because the hermes-agent service runs as user=j_kro
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
  # Note: profiles.role.mining enables services.mining automatically

  # ============================================================================
  # FLATPAK - Flatpak support with Discover and Flathub
  # ============================================================================

  # ============================================================================
  # PER-GPU POWER LIMITS
  # ============================================================================
  # NOTE: Power limits are now managed by the mining.nix module via
  # nvidia-gpu-power-limit.service using perGpuPowerLimits configuration.
  # The old gpu-0-power-limit and gpu-1-power-limit services have been
  # removed to avoid conflicts. Current limits: 3090 @ 250W (3060 Ti disabled).
  #
  # See: modules/mining/mining.nix -> nvidia-gpu-power-limit.service

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
  # Base Tailscale configuration provided by node-profiles.zephyr-workstation
  # No additional network profile configuration needed

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
    opencode # AI coding agent (terminal-based)

    # Mining (manual only, no auto-start)
    xmrig
    lolminer

    # Desktop
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
    telegram-desktop

    # Network automation - for switch/modem configuration scripts
    python3Packages.playwright
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

  # ============================================================================
  # LLAMAFILE - STANDALONE LLM FALLBACK
  # ============================================================================
  # llama.cpp provides a standalone LLM fallback using llama-server
  # Uses Qwen3.5-4B-IQ4_NL (2.4GB) - fits in 8GB VRAM with full offload
  # Runs on port 8083 (8081/8082 used by xmrig, 8080 used by LM Studio)
  services.llamafile = {
    enable = true;
    modelPath = "/home/j_kro/.lmstudio/models/mradermacher/Crow-4B-Opus-4.6-Distill-Heretic_Qwen3.5-i1-GGUF/Crow-4B-Opus-4.6-Distill-Heretic_Qwen3.5.i1-IQ4_NL.gguf";
    host = "0.0.0.0"; # Accept cluster connections
    port = 8083;
    gpu = "vulkan"; # Use Vulkan universal GPU backend (works with NVIDIA and AMD)
    gpuLayers = 999; # Full offload to 3060Ti (2.4GB fits in 8GB VRAM)
    ctxSize = 16384; # 16K context (safe for VRAM)
    threads = 8;
  };

  # ============================================================================

  # ============================================================================
  # HERMES AGENT - Multi-Host Orchestration
  # ============================================================================
  # Autonomous agent for cluster-wide task execution and coordination
  # Uses MCP protocol for inter-service communication
  services.hermes-agent = {
    enable = true;
    user = "j_kro"; # Use existing user
    sharedStorage = {
      enable = true;
      mountPoint = "/home/j_kro/.hermes";
      nfsServer = "10.1.1.120"; # Nexus
      nfsPath = "/data/home"; # Fixed: matches actual NFS export on nexus
    };
    aiGateway = {
      enable = true;
      url = "http://127.0.0.1:8080/v1";
    };
    terminal = {
      enable = true;
      requireApproval = false;
    };
  };

  # ============================================================================

  # ============================================================================
  # SYSTEM STATE
  # ============================================================================
  system.stateVersion = "26.05";

  # ============================================================================
  # CRASH DETECTION
  # ============================================================================
  # Enable crash watchdog to detect and log system crashes
  # Configured in services block above

  # ============================================================================
  # BACKUP TO GARAGE S3
  # ============================================================================
  # Automated daily backups to Garage S3 cluster (runs at 2 AM)
  # Configured in services block above
}
# Force rebuild - Thu 12 Mar 2026 09:59:02 PM UTC
