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
      enable = true;
      nvidia.enable = true;
      role = "agent";
      nodeName = "zephyr";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = cluster.hosts.zephyr.ip;
    };

    k8s-secret-bootstrap = {
      enable = true;
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
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 80;
    };

    backup-to-garage = {
      enable = true;
      endpoint = "http://${cluster.hosts.zephyr.ip}:3900";
      region = "garage";
      bucket = "backups";
      secretKeyFile = "/run/secrets/garage-s3-secret-key";
      retentionDays = 30;
      startAt = "02:00";
    };

    gaming-detection = {
      enable = true;
      checkInterval = 10;
    };

    nexus-exec = {
      enable = true;
    };

    gpu-profile-manager = {
      enable = true;
      checkInterval = 10;
    };

    lpminer = {
      enable = true;
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
      enable = true;
      clusterSync.enable = true; # skip SSH sync to cluster nodes on every activation
    };

    nixos-share = {
      enable = true;
      server.enable = true;
    };

    # NFS server for /etc/nixos only — hermes/pi moved to Nexus to break I/O loop on root NVMe
    nfs-data-server = {
      enable = true;
      exports = "";
    };

    # Sync hermes/pi state FROM Nexus (Nexus is now canonical source)
    nfs-state-sync = {
      enable = true;
      sourceHost = "nexus";
      paths = ["/data/hermes"];
      interval = "15min";
    };

    nfs-client = {
      enable = true;
      mountShared = false;
      mountHome = false;
      mountMedia = false;
    };

    # Caddy — only Tailscale ingress for this host
    # All .lan services moved to nexus (OOM prevention)
    # Uses caddy-with-modules (includes caddy-ratelimit, caddy-security, caddy-cache)
    caddy = {
      enable = true;
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
      enable = true;
      backend = {
        url = "http://127.0.0.1:30880"; # Proxy to K8s gateway
        type = "llama-cpp";
        local = {
          url = "http://127.0.0.1:30880";
          model = "qwen3.6-35b-a3b";
        };
        nvidia-nim = {
          enable = true;
          apiKeyFile = "/run/secrets/nvidia-api-key";
        };
        zai = {
          enable = true;
          apiKeyFile = "/run/secrets/zai-api-key";
          baseUrl = "https://api.z.ai/api/coding/paas/v4";
          enableRetry = true;
          maxRetries = 3;
          retryDelay = 1.0;
          timeout = 300.0;
        };
        pollinations = {
          enable = true;
          apiKeyFile = "/run/secrets/pollinations-api-key";
          baseUrl = "https://text.pollinations.ai";
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
      security = {
        maxRequestSize = 10485760;
        enableProxy = false;
      };
    };

    mcp-servers = {
      enable = true;
    };

    mcp-registry = {
      enable = true;
      generateHermes = true;
      generateClaudeCode = true;
      generateKagentCRDs = true;
      generateNetworkPolicies = true;
      generateCasdoorApps = true;
    };

    cachix-auth = {
      enable = true;
    };

    ai-coding-tools = {
      enable = true;
      user = "j_kro";
      zaiApiKeyFile = "/run/secrets/zai-api-key";
      context7ApiKeyFile = "/run/secrets/context7-api-key";
      nvidiaNimApiKeyFile = "/run/secrets/nvidia-api-key";
      opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
      tools = {
        claude = {enable = true;};
        opencode = {enable = true;};
        droid = {enable = true;};
        crush = {enable = true;};
        pi = {enable = true;};
        omp = {enable = true;};
      };
      enableShellEnv = true;
    };
  };
  programs = {
    haven-desktop.enable = true;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  services.appimage-updater.enable = true;

  services.sops-secrets-registry = {
    enable = true;
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
    enable = true;
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = true;
  services.secret-hygiene.enable = true;
  services.btrfs-boot-snapshot.enable = lib.mkForce false; # NixOS generations sufficient

  # Create directories for hermes/pi bind mounts on Zephyr
  systemd.tmpfiles.rules = [
    "d /data/hermes 0775 j_kro j_kro -"
  ];
  services.syncthing-cluster.enable = true;
}