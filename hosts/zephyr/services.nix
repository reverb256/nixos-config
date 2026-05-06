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
    voxtype = {
      enable = true;
      model = "base.en";
      language = "en";
    };

    hermes-workspace.enable = true;
    hermes-cli = {
      enable = true;
      apiKeyFile = config.age.secrets.zai-api-key.path;
      nvidiaApiKeyFile = config.age.secrets.nvidia-api-key.path;
      casdoorJwtFile = config.age.secrets.casdoor-hermes-jwt.path;
    };
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      nodeName = "zephyr";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = cluster.hosts.zephyr.ip;
      calico.enable = false;
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
      ];
    };

    keepalived-vip = {
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 110;
    };

    backup-to-garage = {
      enable = true;
      endpoint = "http://${cluster.hosts.zephyr.ip}:3900";
      region = "garage";
      bucket = "backups";
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
      enable = true;  # script built here; runs as K8s DaemonSet (systemd masked)
      llamaPort = 1237; # monitor zephyr 3090 llama-server (port 1237)
      primaryMiner = "deployment/gpu-miner-zephyr";
      fallbackMiner = ""; # 3060 Ti reserved for vLLM — no mining fallback
      namespace = "mining";
      checkInterval = 3;
      idleTimeout = 30;
    };

    opencode.enable = true;

    binary-cache.enable = false; # unused, was burning CPU on crash-loop

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

    # Canonical NFS server for hermes + pi agent state
    nfs-data-server = {
      enable = true;
      exports = ''
        /data/hermes 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=105)

        /data/pi 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=106)
      '';
    };

    nfs-client = {
      enable = true;
      mountShared = false;
      mountHome = false;
      mountMedia = false;
    };

    # Caddy — only Tailscale ingress for this host
    # All .lan services moved to nexus (OOM prevention)
    caddy = {
      enable = true;
      configFile = let
        lanRoutes = import ./caddy-routes.nix {inherit cluster;};
      in
        pkgs.writeText "Caddyfile" ''
          {
            admin 127.0.0.1:2019
            default_sni cluster.local
          }

          ai.zephyr.taila21e09.ts.net:9002 {
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
          ${lanRoutes}
        '';
    };

    redis.servers."".enable = false; # 0 keys, 1 client — unused, frees RAM on OOM-constrained host

    # ai-inference: Uses K8s gateway (30880) via Caddy routing
    # Keep config for declarative completeness but backend routes to K8s
    ai-inference = {
      enable = true;
      backend = {
        url = "http://127.0.0.1:30880";  # Proxy to K8s gateway
        type = "llama-cpp";
        local = {
          url = "http://127.0.0.1:30880";
          model = "qwen3.6-35b-a3b";
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
      servers.playwright.enable = true;
      servers.context7.apiKeyFile = "/run/agenix/context7-api-key";
    };

    ai-coding-tools = {
      enable = true;
      zaiApiKeyFile = config.age.secrets.zai-api-key.path;
      context7ApiKeyFile = "/run/agenix/context7-api-key";
    };

    web-testing.enable = true;

    ci-runner = {
      enable = false;
      repo = "username/nixos-config";
      autoStart = false;
    };

    mining = {
      lolminer = {
        pool = "stratum+tcp://${cluster.kubernetes.services.xmrig-proxy.host}:${toString cluster.kubernetes.services.xmrig-proxy.port}";
        wallet = "krxXVNVMM7.zephyr-gpu";
        pools = [
          {
            url = "stratum+tcp://${cluster.kubernetes.services.xmrig-proxy.host}:${toString cluster.kubernetes.services.xmrig-proxy.port}";
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
        enable = false; # Use K8s deployment gpu-miner-zephyr instead (coordinated with gaming/inference)
        autostart = false;
        devices = "1"; # RTX 3090 only (3060 Ti idle for power envelope)
        perGpuPowerLimits = [
          0 # unused
          250 # RTX 3090
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
        pool = "${cluster.hosts.zephyr.ip}:3333";
        wallet = "zephyr-cpu";
        password = "x";
        tls = false;
      };
    };

    # Migrated to K8s auth namespace
    central-auth.enable = false;
    # Vaultwarden migrated to K8s on nexus (vaultwarden.lan via Caddy)
    vaultwarden-module.enable = false;

    syncthing-cluster = {
      enable = true;
      deviceId = "ZEPHYR-PLACEHOLDER";
    };

    garage-cluster.enable = false;

    status-auto-update.enable = true;

    systemd-user-timeout.enable = true;

    cluster-ca.enable = true;

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

  programs = {
    haven-desktop.enable = true;
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  services.appimage-updater.enable = true;

  services.agenix-secrets-registry = {
    enable = true;
    aiServices = true;
    monitoring = false;
    storage = true;
    mining = true;
    cloud = true;
    kubernetes = true;
    initrdRecovery = true;
    selfHosting = true;
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

  # Initrd SSH recovery + BTRFS snapshots
  services.initrd-ssh-recovery = {
    enable = true;
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  # Mask mining-inference-coordinator systemd service — runs as K8s DaemonSet instead
  systemd.services.mining-inference-coordinator = {
    wantedBy = lib.mkForce [];
  };

  services.recovery-specialisation.enable = true;
  services.btrfs-boot-snapshot = {
      enable = true;
      device = "/dev/disk/by-uuid/b07258b9-b1a3-4540-ae34-69e441faba28";
    };
}
