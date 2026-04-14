# Zephyr Service Configuration
# Kubernetes control plane, VIP failover, AI inference, mining,
# backup, monitoring agents, and application services
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  # ============================================================================
  # SERVICES - All service configurations
  # ============================================================================
  services = {
    # KUBERNETES - k3s control plane (joins existing cluster)
    # Bootstrap node: nexus (clusterInit=true, oldest etcd data)
    # All servers join via VIP for HA: https://10.1.1.100:6443
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      nodeName = "zephyr";
      serverAddr = "https://10.1.1.100:6443";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = "10.1.1.110";
      calico.enable = false; # Flannel + kube-proxy (nft segfaults on CachyOS 6.19.11)
    };

    # Deploy K8s manifests from Nix store on boot (control-plane node)
    # DISABLED: easykubenix modules overwrite working mining deployments with
    # broken nix-csi scratch images. Re-enable when easykubenix modules are fixed.
    # k8s-nix-deploy.enable = true;

    # Keepalived VIP for HA API server access
    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "enp38s0";
      priority = 110;
    };

    # Crash watchdog - detect and log system crashes
    # TEMPORARILY DISABLED: Module being fixed (2026-03-23)
    # crash-watchdog.enable = true;

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

    # ============================================================================
    # Modular Workload Monitoring
    # ============================================================================
    # Replaced old compute-workload-monitor monolith with:
    # - gaming-detection: Pure sensor (GameMode + GPU fallback)
    # - gpu-profile-manager: GPU power profile actuator (nvidia-smi)
    # - mining-coordinator: PSI build detection + K8s Volcano preemption
    gaming-detection = {
      enable = true;
      checkInterval = 10;
    };

    gpu-profile-manager = {
      enable = true;
      checkInterval = 10;
    };

    mining-coordinator = {
      enable = true;
      checkInterval = 10;
      # Use conservative thresholds for memory-constrained system
      psiCpuBuildThreshold = "5.0";
      psiCpuIdleThreshold = "2.0";
    };

    # AI CODING AGENT - OpenCode with Kubernetes gateway
    opencode.enable = true;

    # NIX BINARY CACHE - Serve pre-built packages to cluster
    # Eliminates redundant builds across nodes, speeds up deployments
    # ENABLED: Required for distributed builds (2026-03-24)
    # Remote nodes need this cache available during builds
    binary-cache = {
      enable = true;
      port = 50000;
      bindAddress = "10.1.1.110";
    };

    # GPU Resource Marketplace - Unified auction engine for GPU allocation
    # Coordinates between mining, Kubernetes, Akash, and gaming workloads
    # DISABLED: Service broken, blocking rebuild (2026-03-21)
    compute-market = {
      enable = false;
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
      # MIGRATED TO KUBERNETES (2026-03-18)
      prometheus = {
        enable = false;
        port = 9200;
      };
    };

    # XMRig Proxy - Centralized stratum proxy for CPU and GPU mining
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
      configFile = pkgs.writeText "Caddyfile" ''
        # Global options
        {
          admin 127.0.0.1:2019
          default_sni cluster.local
        }

        # AI Inference Gateway (via Tailscale)
        ai.zephyr.tigris-ule.ts.net:9002 {
          header {
            Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            Referrer-Policy "strict-origin-when-cross-origin"
            -Server
          }
          encode zstd gzip
          reverse_proxy 127.0.0.1:8080
        }

        # Host Dashboard (LAN access - no TLS)
        http://zephyr.lan {
          header {
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            -Server
          }
          encode zstd gzip
          reverse_proxy 127.0.0.1:8090
        }
        http://dashboard.zephyr.lan {
          header {
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            -Server
          }
          encode zstd gzip
          reverse_proxy 127.0.0.1:8090
        }

        # Kubernetes Ingress (proxy to Caddy ingress controller on Nexus)
        # Using IP directly — Caddy's Go resolver ignores /etc/hosts
        # TLS via Caddy's internal CA (trusted by zen-browser)
        https://search.lan, https://search.cluster.local {
          encode zstd gzip
          reverse_proxy 10.1.1.120:30080
        }
        https://ai.lan, https://ai.cluster.local {
          encode zstd gzip
          reverse_proxy 10.1.1.120:30080
        }
        https://openwebui.lan, https://openwebui.cluster.local {
          encode zstd gzip
          reverse_proxy 10.1.1.120:30080
        }

        # CivicIntel — Canadian Government Intelligence Dashboard
        http://civicintel.lan, http://10.1.1.100 {
          encode zstd gzip
          handle_path /CivicIntel/* {
            reverse_proxy 10.1.1.120:30085
          }
          handle_path /CivicIntel {
            redir /CivicIntel/ permanent
          }
        }
      '';
    };

    # Spacebot AI agent (integrated with AI Gateway)
    spacebot = {
      enable = true;
      useGateway = true;
      gatewayUrl = "http://127.0.0.1:8081"; # K8s gateway (hostNetwork, port 8081)
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

    # AI Inference Service - Gateway with ALL FEATURES enabled
    ai-inference = {
      enable = true;
      backend = {
        url = "http://127.0.0.1:1235";
        type = "llama-cpp";
        local = {
          url = "http://127.0.0.1:1235";
          model = "gemma-4-e4b-it";
        };
        nvidia-nim = {
          enable = true;
          apiKeyFile = "/run/agenix/nvidia-api-key";
        };
        zai = {
          enable = true;
          apiKeyFile = "/run/agenix/zai-api-key";
          baseUrl = "https://api.z.ai/api/coding/paas/v4";
          enableRetry = true;
          maxRetries = 3;
          retryDelay = 1.0;
          timeout = 300.0;
        };
        pollinations = {
          enable = true;
          apiKeyFile = "/run/agenix/pollinations-api-key";
          baseUrl = "https://text.pollinations.ai";
        };
      };
      gateway = {
        enable = true;
        host = "0.0.0.0";
        port = 8080;
        workers = 1;
        middleware.redis.enable = true;
        middleware.knowledgeFabric = {
          enable = true;
          rrf_k = 60;
          rag_enabled = true;
          searxng_enabled = true;
          searxng_url = "http://10.1.1.120:30808";
          searxng_max_results = 10;
          code_search_enabled = true;
          code_search_paths = [
            "/etc/nixos"
            "/home/j_kro"
          ];
          code_max_results = 10;
          web_search_enabled = true;
          web_max_results = 10;
          rag_top_k = 10;
          brain_wiki_enabled = true;
          brain_wiki_path = "/home/j_kro/brain/wiki";
          brain_wiki_max_results = 5;
          brain_wiki_max_chunk_chars = 2000;
        };
      };
      routing = {
        enable = true;
        defaultModel = "qwen3.5-35b-a3b";
        fallbackChain = [
          "vllm"
          "zai"
          "pollinations"
        ];
      };
      auth.mode = "none";
      monitoring.enable = true;
      rateLimit.enable = true;
      rateLimit.requestsPerMinute = 120;
      systemPrompts = {
        enable = true;
        default = "You are a helpful AI assistant with access to comprehensive knowledge sources.";
        coding = "You are an expert coding assistant. Write clean, efficient, and well-documented code. Use the retrieved knowledge to provide accurate implementations.";
        reasoning = "You are an expert reasoning assistant. Think step-by-step and provide clear explanations backed by retrieved information.";
        analysis = "You are an expert analysis assistant. Provide thorough and structured analysis using multiple sources.";
        agentic = "You are an autonomous agent capable of multi-step planning and execution. Use available tools to complete complex tasks.";
        fast = "You are a fast and efficient assistant. Provide concise, direct answers.";
        custom = {
          nixos = "You are a NixOS configuration expert. Always use lib.mkOptionDefault for shared modules. Reference the cluster documentation.";
          kubernetes = "You are a Kubernetes expert. Use best practices for manifests, deployments, and troubleshooting.";
        };
      };
      mcp = {
        enable = true;
        servers = {
          nix-rebuild = {
            type = "local";
            command = [
              "${(pkgs.python3.withPackages (ps: [ps.mcp])).interpreter}"
              "/etc/nixos/skills/nix-rebuild-mcp/server.py"
            ];
            environment.NIX_HOST = "zephyr";
            environment.NIX_ACCEPT_FLAKE_CONFIG = "1";
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
          context7 = {
            type = "local";
            command = ["/run/current-system/sw/bin/mcp-context7"];
            environment.CONTEXT7_API_KEY_FILE = "/run/agenix/context7-api-key";
            enabled = true;
          };
          searxng = {
            type = "local";
            command = [
              "python3"
              "-m"
              "ai_inference_gateway.mcp_servers.searxng_server"
            ];
            environment = {
              SEARXNG_URL = "http://searxng.search.svc.cluster.local:8080";
              SEARXNG_CACHE_TTL = "300";
            };
            enabled = true;
          };
        };
      };
      rag = {
        enable = true;
        qdrantUrl = "http://127.0.0.1:6333";
        embeddingModel = "sentence-transformers/all-MiniLM-L6-v2";
        chunkSize = 512;
        chunkOverlap = 50;
        topK = 10;
        hybridSearch = {
          enable = true;
          vectorWeight = 0.7;
          bm25Weight = 0.3;
        };
        autoRag = {
          enable = true;
          threshold = 0.3;
        };
        tokenScopedCollections = true;
        reranker = {
          enable = true;
          model = "BAAI/bge-reranker-v2-base";
        };
        qdrant = {
          enable = true;
          host = "127.0.0.1";
          port = 6333;
          grpcPort = 6334;
          storagePath = "/var/lib/qdrant";
          memoryLimit = "4G";
        };
      };
      security = {
        maxRequestSize = 10485760; # 10MB
        enableProxy = false;
      };
    };

    # MCP Servers for AI tools
    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
      servers.context7.apiKeyFile = "/run/agenix/context7-api-key";
    };

    # AI Coding Tools - Harmonized MCP configs
    ai-coding-tools = {
      enable = true;
      zaiApiKeyFile = config.age.secrets.zai-api-key.path;
      context7ApiKeyFile = "/run/agenix/context7-api-key";
      tools.pi.packages = [
        "npm:pi-annotated-reply@0.4.1"
        "npm:pi-btw@0.2.1"
        "npm:pi-context@1.1.2"
        "npm:pi-lens@3.8.5"
        "npm:pi-mcp-adapter@2.2.2"
        "npm:pi-powerline-footer@0.4.9"
        "npm:pi-rewind@0.5.0"
        "npm:pi-show-diffs@0.2.7"
        "npm:pi-subagents@0.12.4"
        "npm:pi-web-access@0.10.6"
        "npm:pi-worktree@1.3.3"
        "npm:pi-self-learning"
      ];
    };

    # WEB TESTING - Playwright/Puppeteer system dependencies
    web-testing.enable = true;

    # CI/CD - Self-hosted GitHub Actions runner
    ci-runner = {
      enable = false;
      repo = "username/nixos-config";
      autoStart = false;
    };

    # MINING - GPU Mining (RTX 3090 + RTX 3060 Ti)
    # Using centralized xmrig-proxy on nexus (10.1.1.120:3333)
    mining = {
      lolminer = {
        pool = "stratum+tcp://10.1.1.120:3333";
        wallet = "krxXVNVMM7.zephyr-gpu";
        pools = [
          {
            url = "stratum+tcp://10.1.1.120:3333";
            wallet = "krxXVNVMM7.zephyr-gpu";
            password = "x";
            tls = false;
          }
          {
            url = "xtm-c29-us.kryptex.network:8040";
            wallet = "krxXVNVMM7.zephyr-gpu";
            password = "x";
            tls = true;
          }
          {
            url = "xtm-c29-eu.kryptex.network:8040";
            wallet = "krxXVNVMM7.zephyr-gpu";
            password = "x";
            tls = true;
          }
        ];
      };
      # NVIDIA GPU mining - MIGRATED TO KUBERNETES
      lolminer.nvidia = {
        enable = false;
        autostart = false;
        devices = "1"; # Only mine on GPU 1 (RTX 3090)
        perGpuPowerLimits = [
          0
          250
        ]; # GPU0: RTX 3060 Ti no limit (AI/ML), GPU1: RTX 3090 @ 250W
        apiPort = 4068;
      };
      # CPU mining - Dual XMRig setup
      xmrigDual = {
        enable = true;
        alwaysOn = {
          enable = false;
          threads = 4;
          httpPort = 8081;
          httpTokenFile = "/run/agenix/xmrig-always-api-token";
          autostart = false;
        };
        flexible = {
          enable = true;
          threads = 12;
          httpPort = 8082;
          httpTokenFile = "/run/agenix/xmrig-flexible-api-token";
          autostart = false;
        };
        pool = "10.1.1.110:3333";
        wallet = "zephyr-cpu";
        password = "x";
        tls = false;
      };
    };

    # Vaultwarden - Self-hosted password manager with FIDO2/WebAuthn
    vaultwarden-module = {
      enable = true;
      hostName = "vaultwarden.zephyr.tigris-ule.ts.net";
      dataDir = "/var/lib/vaultwarden";
    };

    # Syncthing P2P file sync
    syncthing-cluster = {
      enable = true;
      deviceId = "ZEPHYR-PLACEHOLDER";
    };

    # Garage S3 disabled - using nexus as primary storage node
    garage-cluster.enable = false;

    # Host Dashboard
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

    # STATUS.md auto-update (hourly from kubectl)
    status-auto-update.enable = true;

    # FIX: Systemd user unit reload timeout
    systemd-user-timeout.enable = true;

    # Internal CA for cluster services
    cluster-ca.enable = true;

    # Unbound DNS with DNS-over-TLS
    unbound-common.enable = true;

    # Claude Code Router - Route Claude Code to Z.AI GLM models
    claude-code-router = {
      enable = true;
      port = 3456;
      openFirewall = false;
      zai = {
        apiKeyFile = config.age.secrets.zai-api-key.path;
        defaultModel = "glm-4.7";
        thinkModel = "glm-4.7";
      };
    };
  };

  # ============================================================================
  # LLAMAFILE - Gemma 4 E4B vision model on 3060 Ti (llama.cpp b8781)
  # ============================================================================
  # Text + Vision via --mmproj, Q4_K_M quant, ~80 tok/s
  services.llamafile = {
    enable = true;
    modelPath = "/home/j_kro/.lmstudio/models/lmstudio-community/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf";
    mmprojPath = "/home/j_kro/.lmstudio/models/lmstudio-community/gemma-4-E4B-it-GGUF/mmproj-gemma-4-E4B-it-BF16.gguf";
    modelName = "gemma4-e4b-vision";
    host = "0.0.0.0";
    port = 8888;
    gpu = "nvidia";
    gpuLayers = 99;
    gpuDevice = 1; # 3060 Ti is CUDA device 1 (3090 is device 0)
    ctxSize = 32768;
    threads = 4;
    flashAttention = true;
    cacheTypeK = "q4_0";
    cacheTypeV = "q4_0";
    temperature = 1.0;
    topK = 64;
    topP = 0.95;
    enableThinking = false; # Disable thinking for vision tasks
  };

  # Ollama removed — llama.cpp with vision (--mmproj) replaces it

  # ============================================================================
  # PROGRAMS - Service-linked programs
  # ============================================================================
  programs = {
    # Mining plasmoid for KDE Plasma
    mining-plasmoid = {
      enable = true;
      prometheusUrl = "http://127.0.0.1:9090";
      refreshInterval = 10000;
      clusterNodes = "zephyr,nexus,forge,sentry";
    };

    # Systems Intelligence Plasmoid - Cluster monitoring widget
    systems-intelligence-plasmoid = {
      enable = true;
      prometheusUrl = "http://127.0.0.1:9090";
      refreshInterval = 5000;
      clusterNodes = "zephyr,nexus,forge,sentry";
    };

    # LM Studio - Local LLM inference with GPU acceleration
    lm-studio.enable = true;
  };

  # Podman container runtime (for Spacebot)
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  # ============================================================================
  # AGENIX SECRETS
  # ============================================================================
  services.agenix-secrets-registry = {
    enable = true;
    aiServices = true;
    monitoring = false;
    storage = true;
    mining = true;
    cloud = true;
    kubernetes = true;
    selfHosting = false;
  };

  # Override specific secret permissions
  age = {
    identityPaths = ["/home/j_kro/.age/key.txt"];
    secrets.cloudflared-token = lib.mkForce {
      file = "${inputs.self}/secrets/cloudflared-token.age";
      mode = "400";
      owner = "root";
      group = "root";
    };
  };
}
