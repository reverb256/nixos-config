{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  services = {
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      nodeName = "zephyr";
      serverAddr = "https://10.1.1.100:6443";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = "10.1.1.110";
      calico.enable = false;
    };


    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "enp38s0";
      priority = 110;
    };


    backup-to-garage = {
      enable = true;
      endpoint = "http://10.1.1.110:3900";
      region = "garage";
      bucket = "backups";
      accessKey = "GKac91d924fc76a30b9bcf6c3e";
      secretKeyFile = "/run/agenix/garage-s3-secret-key";
      retentionDays = 30;
      startAt = "02:00";
    };

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
      psiCpuBuildThreshold = "5.0";
      psiCpuIdleThreshold = "2.0";
    };

    mining-inference-coordinator = {
      enable = true;
      llamaPort = 1235;
      primaryMiner = "deployment/gpu-miner-zephyr";
      fallbackMiner = "deployment/gpu-miner-zephyr-3060ti";
      namespace = "mining";
      checkInterval = 3;
      idleTimeout = 30;
    };

    opencode.enable = true;

    binary-cache = {
      enable = true;
      port = 50000;
      bindAddress = "10.1.1.110";
    };

    compute-market = {
      enable = false;
      auctionInterval = 30;

      bidders = {
        mining = {
          enable = true;
          hourlyRevenue = 0.10;
          services = [
            "lolminer-nvidia"
            "xmrig"
          ];
        };

        kubernetes = {
          enable = true;
          baseBid = 2.50;
          urgencyMultiplier = 2.0;
          namespace = "default";
        };

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

      prometheus = {
        enable = false;
        port = 9200;
      };
    };

    xmrig-proxy = {
      enable = true;

      config = builtins.toJSON {
        pools = [
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

    nixos-share = {
      enable = true;
      server.enable = true;
    };

    nfs-client = {
      enable = true;
      mountShared = false;
      mountHome = false;
      mountMedia = false;
    };

    caddy = {
      enable = true;
      configFile = pkgs.writeText "Caddyfile" ''
        {
          admin 127.0.0.1:2019
          default_sni cluster.local
        }

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

        https://search.lan, https://search.cluster.local {
          tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key
          encode zstd gzip
          reverse_proxy 10.1.1.120:30888
        }
        https://ai.lan, https://ai.cluster.local {
          tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key
          encode zstd gzip
          reverse_proxy 10.1.1.120:8080
        }
        https://openwebui.lan, https://openwebui.cluster.local {
          tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key
          encode zstd gzip
          reverse_proxy 10.1.1.120:32080
        }

        https://haven.lan, https://haven.cluster.local {
          tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key
          encode zstd gzip
          reverse_proxy 10.1.1.120:3000
        }

        https://hermes.lan, https://hermes.cluster.local {
          tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key
          encode zstd gzip
          reverse_proxy 10.1.1.120:9119
        }

        https://api.hermes.lan {
          tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key
          encode zstd gzip
          reverse_proxy 10.1.1.120:8642
        }
      '';
    };

    redis.servers."".enable = true;

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
        enable = false; # Use nexus gateway instead (saves ~140MB RAM on zephyr)
        host = "0.0.0.0";
        port = 8080;
        workers = 1;
        middleware.redis.enable = true;
        middleware.knowledgeFabric = {
          enable = true;
          rrf_k = 60;
          rag_enabled = true;
          searxng_enabled = true;
          searxng_url = "http://10.1.1.120:30888";
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
        enable = false;
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
        enable = false;
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
        maxRequestSize = 10485760;
        enableProxy = false;
      };
    };

    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
      servers.context7.apiKeyFile = "/run/agenix/context7-api-key";
    };

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

    web-testing.enable = true;

    ci-runner = {
      enable = false;
      repo = "username/nixos-config";
      autoStart = false;
    };

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
      lolminer.nvidia = {
        enable = true;
        autostart = true;
        devices = "1"; # RTX 3090 only (3060 Ti idle for power envelope)
        perGpuPowerLimits = [
          0    # unused
          250  # RTX 3090
        ];
        apiPort = 4068;
      };
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

    vaultwarden-module = {
      enable = true;
      hostName = "vaultwarden.zephyr.tigris-ule.ts.net";
      dataDir = "/var/lib/vaultwarden";
    };

    syncthing-cluster = {
      enable = true;
      deviceId = "ZEPHYR-PLACEHOLDER";
    };

    garage-cluster.enable = false;

    status-auto-update.enable = true;

    systemd-user-timeout.enable = true;

    cluster-ca.enable = true;

    unbound-common.enable = true;

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

  services.llamafile = {
    enable = false; # Migrated to k8s
    modelPath = "/home/j_kro/.lmstudio/models/lmstudio-community/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf";
    mmprojPath = "/home/j_kro/.lmstudio/models/lmstudio-community/gemma-4-E4B-it-GGUF/mmproj-gemma-4-E4B-it-BF16.gguf";
    modelName = "gemma4-e4b-vision";
    host = "0.0.0.0";
    port = 1235;
    gpu = "nvidia";
    gpuLayers = 99;
    gpuDevice = 1;
    ctxSize = 131072;
    threads = 4;
    flashAttention = true;
    cacheTypeK = "q4_0";
    cacheTypeV = "q4_0";
    temperature = 1.0;
    topK = 64;
    topP = 0.95;
    enableThinking = false;
  };


  programs = {
    mining-plasmoid = {
      enable = true;
      prometheusUrl = "http://127.0.0.1:9090";
      refreshInterval = 10000;
      clusterNodes = "zephyr,nexus,forge,sentry";
    };

    systems-intelligence-plasmoid = {
      enable = true;
      prometheusUrl = "http://127.0.0.1:9090";
      refreshInterval = 5000;
      clusterNodes = "zephyr,nexus,forge,sentry";
    };

    lm-studio.enable = true;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

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
