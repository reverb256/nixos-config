{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  cluster = config.networking.cluster;
in {
  services = {
#    hermes-cli = {
#      enable = lib.mkForce false;
#      model = "base.en";
#      apiKeyFile = "/run/secrets/zai-api-key";
#      nvidiaApiKeyFile = "/run/secrets/nvidia-api-key";
#      casdoorJwtFile = "/run/secrets/casdoor-hermes-jwt";
#      opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
#      # openrouterApiKeyFile removed — no longer used
#      kilocodeApiKeyFile = "/run/secrets/kilo-api-key";
#      geminiApiKeyFile = "/run/secrets/gemini-api-key";
#      hfTokenFile = "/run/secrets/huggingface-token";
#      githubTokenFile = "/run/secrets/github-token";
#      settings = {
#        model = {
#          provider = "gateway";
#          default = "opencode-go/deepseek-v4-flash";
#        };
#        toolsets = ["all"];
#        terminal = {
#          backend = "local";
#          timeout = 180;
#        };
#        memory = {
#          memory_enabled = true;
#          user_profile_enabled = true;
#        };
#        compression = {
#          enabled = true;
#          threshold = 0.9;
#        };
#      };
#    };
    k3s-cluster = {
      enable = lib.mkForce false;
      nvidia.enable = lib.mkForce false;
      role = "agent";
      nodeName = "zephyr";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = cluster.hosts.zephyr.ip;
    };

    k8s-secret-bootstrap = {
      enable = lib.mkForce false;
      secrets = [
        {
          namespace = "auth";
          name = "casdoor-postgres-secret";
          keys = ["POSTGRES_PASSWORD"];
        }
        {
          namespace = "auth";
          name = "oauth2-proxy-secrets";
          keys = ["client-secret" "cookie-secret"];
        }
        {
          namespace = "automation";
          name = "n8n-secrets";
          keys = ["postgres-password"];
        }
        {
          namespace = "mcp";
          name = "grafana-admin-secret";
          keys = ["admin-password"];
        }
      ];
    };

    # Disabled: zephyr is now a k3s agent (not server), so the VIP
    # should live on the server nodes (sentry) for k3s API access.
    keepalived-vip = {
      enable = lib.mkForce false;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 80;
    };

    backup-to-garage = {
      enable = lib.mkForce false;
      endpoint = "http://${cluster.hosts.zephyr.ip}:3900";
      region = "garage";
      bucket = "backups";
      secretKeyFile = "/run/secrets/garage-s3-secret-key";
      retentionDays = 30;
      startAt = "02:00";
    };

    gaming-detection = {
      enable = lib.mkForce false;
      checkInterval = 10;
    };

    nexus-exec = {
      enable = lib.mkForce false;
    };

    gpu-profile-manager = {
      enable = lib.mkForce false;
      checkInterval = 10;
    };

    lpminer = {
      enable = lib.mkForce false;
      instances = [
        {
          name = "3060ti";
          gpuId = 0;
          wallet = "krxXVNVMM7.zephyr-3060ti";
          powerLimit = 100;
          pool = "stratum+ssl://prl-us.kryptex.network:8048,stratum+ssl://prl.kryptex.network:8048";
        }
        {
          name = "3090";
          gpuId = 1;
          wallet = "krxXVNVMM7.zephyr-3090";
          powerLimit = 150;
          pool = "stratum+ssl://prl-us.kryptex.network:8048,stratum+ssl://prl.kryptex.network:8048";
        }
      ];
    };

    opencode = {
      enable = lib.mkForce false;
      clusterSync.enable = lib.mkForce false; # skip SSH sync to cluster nodes on every activation
    };

    nixos-share = {
      enable = lib.mkForce false;
      server.enable = lib.mkForce false;
    };

    # NFS server for /etc/nixos only — hermes/pi moved to Nexus to break I/O loop on root NVMe
    nfs-data-server = {
      enable = lib.mkForce false;
      exports = "";
    };

    # Sync hermes/pi state FROM Nexus (Nexus is now canonical source)
    nfs-state-sync = {
      enable = lib.mkForce false;
      sourceHost = "nexus";
      paths = ["/data/hermes"];
      interval = "15min";
    };

    nfs-client = {
      enable = lib.mkForce false;
      mountShared = false;
      mountHome = false;
      mountMedia = false;
    };

    # Caddy — only Tailscale ingress for this host
    # All .lan services moved to nexus (OOM prevention)
    # Uses caddy-with-modules (includes caddy-ratelimit, caddy-security, caddy-cache)
    caddy = {
      enable = lib.mkForce false;
      package = pkgs.caddy-with-modules;
      configFile = let
        lanRoutes = import ./caddy-routes.nix {inherit cluster;};
      in
        pkgs.writeText "Caddyfile" ''
          {
            admin 127.0.0.1:2019
            auto_https off
            default_sni cluster.local
          }

          # ── Tailscale Funnel Route (public-facing) ──────────────
          # Rate limited: 100 req/min per IP to protect against brute force/DDoS.
          # Requires caddy-with-modules (mholt/caddy-ratelimit plugin).
          ai.zephyr.taila21e09.ts.net:9002 {
            rate_limit {
              zone funnel_per_ip {
                key    {remote_host}
                events 100
                window 1m
              }
            }
            forward_auth 127.0.0.1:30890 {
              uri /oauth2/auth
              copy_headers X-Auth-Request-User X-Auth-Request-Email X-Auth-Request-Preferred-Username
              handle_response {
                @is401 expression {http.reverse_proxy.status_code} == 401
                redir @is401 https://auth.lan/oauth2/start?rd={scheme}://{host}{uri} temporary
              }
            }
            header {
              Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
              X-Content-Type-Options "nosniff"
              X-Frame-Options "SAMEORIGIN"
              Referrer-Policy "strict-origin-when-cross-origin"
              -Server
            }
            encode zstd gzip
            reverse_proxy 127.0.0.1:30880
          }
          ${lanRoutes}
        '';
    };

    # ai-inference: Uses K8s gateway (30880) via Caddy routing
    # Keep config for declarative completeness but backend routes to K8s
    ai-inference = {
      enable = lib.mkForce false;
      backend = {
        url = "http://127.0.0.1:30880"; # Proxy to K8s gateway
        type = "llama-cpp";
        local = {
          url = "http://127.0.0.1:30880";
          model = "qwen3.6-35b-a3b";
        };
        nvidia-nim = {
          enable = lib.mkForce false;
          apiKeyFile = "/run/secrets/nvidia-api-key";
        };
        zai = {
          enable = lib.mkForce false;
          apiKeyFile = "/run/secrets/zai-api-key";
          baseUrl = "https://api.z.ai/api/coding/paas/v4";
          enableRetry = true;
          maxRetries = 3;
          retryDelay = 1.0;
          timeout = 300.0;
        };
        pollinations = {
          enable = lib.mkForce false;
          apiKeyFile = "/run/secrets/pollinations-api-key";
          baseUrl = "https://text.pollinations.ai";
        };
      };
      routing = {
        enable = lib.mkForce false;
        defaultModel = "qwen3.5-35b-a3b";
        fallbackChain = [
          "vllm"
          "zai"
          "pollinations"
        ];
      };
      auth.mode = "none";
      monitoring.enable = lib.mkForce false;
      rateLimit.enable = lib.mkForce false;
      rateLimit.requestsPerMinute = 120;
      systemPrompts = {
        enable = lib.mkForce false;
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
      security = {
        maxRequestSize = 10485760;
        enableProxy = false;
      };
    };

    mcp-servers = {
      enable = lib.mkForce false;
    };

    mcp-registry = {
      enable = true;
      generateHermes = true;
      generateClaudeCode = true;
      generateNetworkPolicies = true;
      generateCasdoorApps = true;
    };

    cachix-auth = {
      enable = lib.mkForce false;
    };

    ai-coding-tools = {
      enable = lib.mkForce false;
      user = "j_kro";
      zaiApiKeyFile = "/run/secrets/zai-api-key";
      context7ApiKeyFile = "/run/secrets/context7-api-key";
      nvidiaNimApiKeyFile = "/run/secrets/nvidia-api-key";
      opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
      tools = {
        claude = {enable = lib.mkForce false;};
        opencode = {enable = lib.mkForce false;};
        droid = {enable = lib.mkForce false;};
        crush = {enable = lib.mkForce false;};
        pi = {enable = lib.mkForce false;};
        omp = {enable = lib.mkForce false;};
      };
      enableShellEnv = true;
    };

    # ── Nix-managed Hermes config.yaml ────────────────────────────
    # Providers, fallback chain, and base_url/key mappings live in Nix.
    # Imperative sections (telegram channel_profiles, MCP servers, etc.)
    # are preserved on disk across rebuilds by systemd hermes-config-emit.
    hermes-cli = {
      enable = true;
      user = "j_kro";
      apiKeyFile = "/run/secrets/zai-api-key";
      nvidiaApiKeyFile = "/run/secrets/nvidia-api-key";
      casdoorJwtFile = "/run/secrets/casdoor-hermes-jwt";
      opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
      opencodeZenApiKeyFile = "/run/secrets/opencode-api-key";
      gatewayUrl = "http://${cluster.hosts.zephyr.ip}:${toString cluster.kubernetes.nodePorts.ai-inference-gateway}/v1";

      managedConfig = true;
      managedProviders = {
        # Cloud-only providers that drive the picker. Local inference
        # (forge/llama-cpp) lives outside this config — exposed via the
        # AI inference gateway and used by smart_model_routing, not the
        # model picker.
        "opencode-zen" = {
          api_key_env = "OPENCODE_API_KEY";
          base_url = "https://opencode.ai/zen/v1";
          discover_models = true;
          model = "nemotron-3-ultra-free";
        };
        "opencode-go" = {
          api_key_env = "OPENCODE_GO_API_KEY";
          base_url = "https://opencode.ai/zen/go/v1";
          discover_models = true;
        };
        "zai" = {
          api_key_env = "ZAI_API_KEY";
          base_url = "https://api.z.ai/api/coding/paas/v4";
          discover_models = true;
          model = "glm-4.7";
        };
        "nvidia" = {
          api_key_env = "NVIDIA_API_KEY";
          base_url = "https://integrate.api.nvidia.com/v1";
          discover_models = true;
        };
      };
      managedFallbackProviders = [
        "opencode-zen"
        "opencode-go"
        "zai"
        "nvidia"
      ];
    };
  };
  programs = {
    haven-desktop.enable = lib.mkForce false;
  };

  virtualisation.podman = {
    enable = lib.mkForce false;
    dockerCompat = true;
    dockerSocket.enable = false;
  };

  services.appimage-updater.enable = lib.mkForce false;

  services.sops-secrets-registry = {
    enable = lib.mkForce false;
    aiServices = true;
    monitoring = false;
    storage = true;
    mining = true;
    cloud = true;
    kubernetes = true;
    automation = true;
    ci = true;
    selfHosting = true;
  };

  # Mining user for secret ownership (ZEPHYR monitors mining but doesn't run workers)
  users.users.mining = {
    isSystemUser = true;
    group = "mining";
    description = "Mining service user";
  };

  users.groups.mining = {};

  # Initrd SSH recovery + BTRFS snapshots
  services.initrd-ssh-recovery = {
    enable = lib.mkForce false;
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = lib.mkForce false;
  services.secret-hygiene.enable = lib.mkForce false;
  services.btrfs-boot-snapshot.enable = lib.mkForce false; # NixOS generations sufficient

  # Create directories for hermes/pi bind mounts on Zephyr
  systemd.tmpfiles.rules = [
    "d /data/hermes 0775 j_kro j_kro -"
  ];
  services.syncthing-cluster.enable = lib.mkForce false;
}