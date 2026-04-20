{ config, pkgs, lib, inputs, ... }:
{
  systemd.tmpfiles.rules = [
    "R /var/lib/etcd - - - - -"
  ];

  services = {
    hermes-cli = {
      enable = true;
      apiKeyFile = config.age.secrets.zai-api-key.path;
      nvidiaApiKeyFile = config.age.secrets.nvidia-api-key.path;
    };
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      clusterInit = true;
      nodeName = "nexus";
      serverAddr = "https://10.1.1.100:6443";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = "10.1.1.120";
      calico.enable = false;
    };

    keepalived-vip = {
      enable = false; # NixOS module not available yet
      vip = "10.1.1.100";
      interface = "enp7s0";
      priority = 100;
    };

    gaming-detection.enable = lib.mkForce false;

    vane = {
      enable = true;
      port = 30900;
      searxngUrl = "http://10.4.98.141:8080"; # K8s search/searxng ClusterIP
      openFirewall = true;
    };

    gpu-profile-manager.enable = lib.mkForce false; # NixOS module not available yet
    mining-coordinator.enable = false; # NixOS module not available yet

    garnix.enable = false; # NixOS module not available yet
    nixos-auto-update.enable = false; # NixOS module not available yet

    spotify-spotx.enable = false; # NixOS module not available yet

    mining = {
      xmrigDual = {
        enable = false;
        alwaysOn = {
          enable = false;
          threads = 4;
          httpPort = 8081;
          httpTokenFile = "/run/agenix/xmrig-always-api-token";
          autostart = false;
        };
        flexible = {
          enable = false; # NixOS module not available yet
          threads = 8;
          httpPort = 8082;
          httpTokenFile = "/run/agenix/xmrig-flexible-api-token";
          autostart = false;
        };
        pool = "10.1.1.110:3333";
        wallet = "nexus-cpu";
        password = "x";
        tls = false;
      };

      lolminer.nvidia = {
        enable = false;
        powerLimit = 120;
      };
    };

    mcp-servers = {
      enable = false; # NixOS module not available yet
      servers.playwright.enable = false; # NixOS module not available yet
      servers.context7.apiKeyFile = "/run/agenix/context7-api-key";
    };

    nixos-share = {
      enable = true;
      client.enable = true;
    };

    nfs.server.enable = true;

    syncthing-cluster = {
      enable = false; # NixOS module not available yet
      deviceId = "NEXUS-PLACEHOLDER";
    };

    garage-cluster = {
      enable = false; # NixOS module not available yet
      dataDir = "/data/shared/garage";
      replicationFactor = 1;
      consistencyMode = "consistent";
      enableMetrics = true;
      enableBackup = false;
    };

    status-auto-update.enable = false; # NixOS module not available yet

    unbound-common.enable = false; # NixOS module not available yet

    ai-coding-tools = {
      enable = false; # NixOS module not available yet
      zaiApiKeyFile = config.age.secrets.zai-api-key.path;
      context7ApiKeyFile = "/run/agenix/context7-api-key";
    };

    agenix-secrets-registry = {
      enable = true;
      aiServices = true;
      monitoring = false;
      storage = true;
      mining = false;
      cloud = false;
      kubernetes = true;
      selfHosting = false;
    };
  };

  programs.steam = {
    enable = lib.mkForce false;
    gamescopeSession.enable = lib.mkForce false;
  };

  environment.systemPackages = with pkgs; [
    llama-cpp
  ];

  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # Hermes Agent — primary user-facing agent
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;

    settings = {
      providers = {
        zai = {
          base_url = "https://api.z.ai/api/coding/paas/v4";
          api_key_env = "ZAI_API_KEY";
          model = "glm-5.1";
        };
        nvidia-nim = {
          base_url = "https://integrate.api.nvidia.com/v1";
          api_key_env = "NVIDIA_API_KEY";
          model = "deepseek-ai/deepseek-v3.1";
        };
        ai-gateway = {
          base_url = "http://127.0.0.1:8080/v1";
          api_key = "none";
          model = "qwen3.5-4b";
        };
        lmstudio = {
          base_url = "http://127.0.0.1:1234/v1";
          api_key = "lmstudio";
          model = "qwen3.5-4b";
        };
        llama-cpp-zephyr = {
          base_url = "http://llama-server-zephyr.ai-inference.svc.cluster.local:1235/v1";
          api_key = "unused";
          model = "Qwen3.6-35B-A3B-UD-Q3_K_M.gguf";
        };
        llama-cpp-sentry = {
          base_url = "http://llama-server-sentry.ai-inference.svc.cluster.local:1235/v1";
          api_key = "unused";
          model = "Qwen3.5-4B.Q4_K_M.gguf";
        };
      };
      fallback_providers = [
        "zai"
        "nvidia-nim"
        "llama-cpp-zephyr"
        "llama-cpp-sentry"
      ];
      smart_model_routing = {
        enabled = true;
        max_simple_chars = 160;
        max_simple_words = 28;
        cheap_model = {
          provider = "llama-cpp-sentry";
          model = "Qwen3.5-4B.Q4_K_M.gguf";
        };
      };
      toolsets = [ "all" ];
      terminal = {
        backend = "local";
        timeout = 180;
      };
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };
      compression = {
        enabled = true;
        threshold = 0.9;
      };
    };

    # Non-secret environment vars — passed via systemd override below
    # (the module's environment option doesn't reliably set systemd env vars)
    environment = {};

    # Secrets loaded via ExecStartPre + EnvironmentFile override below
    # environmentFiles = [ config.age.secrets.hermes-env.path ];

    # MCP servers
    mcpServers = {
      github = {
        command = "npx";
        args = [ "-y" "@modelcontextprotocol/server-github" ];
      };
    };

    # Personality documents
    documents = {
      "SOUL.md" = ''
        You are Hermes, the primary AI agent for a NixOS cluster.
        You manage infrastructure, coding tasks, and daily operations.
        For coding tasks, delegate to the pi-coder MCP server.
        Always prefer local, self-hosted solutions.
      '';
    };

    extraPackages = with pkgs; [ git ripgrep curl jq ];
  };

  # Hermes web dashboard
  services.hermes-dashboard = {
    enable = false;
    port = 9119;
    host = "0.0.0.0";
    openFirewall = true;
  };

  # Load Z.AI and NVIDIA API keys for hermes-agent
  # The official module's environment option doesn't reliably set systemd env vars,
  # so we use a systemd override with ExecStartPre to generate an env file.
  systemd.services.hermes-agent = {
    serviceConfig.ExecStartPre = "+" + (pkgs.writeShellScript "hermes-load-env" ''
      mkdir -p /data/hermes/.hermes
      cat > /data/hermes/.hermes/provider-env << 'ENVEOF'
      API_SERVER_ENABLED=true
      API_SERVER_HOST=0.0.0.0
      API_SERVER_PORT=8642
      API_SERVER_KEY=hermes-local-dev-b8b2275d6053fb335a9508048c54dc96
      GLM_BASE_URL=https://api.z.ai/api/coding/paas/v4
      NVIDIA_BASE_URL=https://integrate.api.nvidia.com/v1
      ENVEOF
      echo -n "ZAI_API_KEY=" >> /data/hermes/.hermes/provider-env
      cat /run/agenix/zai-api-key >> /data/hermes/.hermes/provider-env
      echo -n "NVIDIA_API_KEY=" >> /data/hermes/.hermes/provider-env
      cat /run/agenix/nvidia-api-key >> /data/hermes/.hermes/provider-env
      chmod 600 /data/hermes/.hermes/provider-env
      chown hermes:hermes /data/hermes/.hermes/provider-env
    '');
    # Use "-" prefix so systemd doesn't fail if file doesn't exist yet
    serviceConfig.EnvironmentFile = "-/data/hermes/.hermes/provider-env";
  };

  # Knowledge Base MCP server — RAG search over 38 ingested books
  # kb-mcp-server: DELETED — replaced by knowledge-fabric
  # brain-wiki-sync: DELETED — wiki pages are display-only, Qdrant is the retrieval path

  users.users.j_kro.extraGroups = [
    "hermes"
    "plugdev"
    "audio"
    "input"
    "docker"
    "openrazer"
    "tailscale"
    "video"
    "render"
  ];

  # Qdrant runs in K8s now — disable the systemd service
  systemd.services.qdrant = {
    enable = false;
  };
}
