{ config, pkgs, lib, inputs, ... }:
let
  # Build the hermes-agent Python venv (same derivation the flake uses for its wrappers)
  hermesVenv = pkgs.callPackage (inputs.hermes-agent.outPath + "/nix/python.nix") {
    inherit (inputs.hermes-agent.inputs) uv2nix pyproject-nix pyproject-build-systems;
  };
  k8s = config.networking.cluster.kubernetes.services;
  cluster = config.networking.cluster;
in {
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
      clusterInit = false;  # Rejoining existing cluster, not bootstrapping
      nodeName = "nexus";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = cluster.hosts.nexus.ip;
      calico.enable = false;
    };

    keepalived-vip = {
      enable = false;
      vip = cluster.kubernetes.vip;
      interface = "enp7s0";
      priority = 100;
    };

    gaming-detection.enable = lib.mkForce false;

    vane.enable = false; # Migrated to K8s (search namespace, easykubenix module)

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
        pool = "${cluster.hosts.zephyr.ip}:3333";
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

    nfs-data-server.enable = true;

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
    nvtopPackages.full
  ];

  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # Hermes Agent — primary user-facing agent
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = false;  # hermes-with-whatsapp (superset) added via hermes-cli.nix

    settings = {
      providers = {
        # All inference through AI Inference Gateway on Nexus:8080
        # Gateway handles upstream routing, auth, think-param stripping
        ai-gateway = {
          base_url = "http://ai-inference.lan:8080/v1";
          api_key = "none";
          model = "qwen/qwen3-coder-480b-a35b-instruct";
        };
        # Direct ZAI fallback (bypasses gateway for reliability)
        zai = {
          base_url = "https://api.z.ai/api/coding/paas/v4";
          api_key_env = "ZAI_API_KEY";
          model = "glm-5.1";
        };
        # NVIDIA NIM cloud models
        nvidia-nim = {
          base_url = "https://integrate.api.nvidia.com/v1";
          api_key_env = "NVIDIA_API_KEY";
          model = "nvidia/llama-3.3-nemotron-super-49b-v1";
        };
        # Local llama-cpp endpoints
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

  # Hermes WebUI — nesquena/hermes-webui
  # Runs the agent in-process (no send-stream hang, no Redis, no proxy needed)
  # Replaces: hermes-dashboard, hermes-merged-proxy, Hermes-Studio
  systemd.services.hermes-webui = {
    description = "Hermes Web UI";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "hermes-agent.service" ];
    wants = [ "hermes-agent.service" ];
    path = with pkgs; [ git coreutils curl jq ];
    environment = {
      AI_GATEWAY_API_KEY = "none";
      HERMES_HOME = "/home/j_kro/.hermes";
      HERMES_WEBUI_HOST = "0.0.0.0";
      HERMES_WEBUI_PORT = "8787";
      HERMES_WEBUI_STATE_DIR = "/home/j_kro/.hermes/webui-mvp";
      HERMES_WEBUI_DEFAULT_WORKSPACE = "/home/j_kro/workspace";
      HERMES_WEBUI_AGENT_DIR = "${hermesVenv}/lib/python3.11/site-packages";
      PYTHONPATH = "${hermesVenv}/lib/python3.11/site-packages";
    };
    serviceConfig = {
      LoadCredential = [ "hermes-webui-password:${config.age.secrets.hermes-webui-password.path}" ];
      ExecStart = pkgs.writeShellScript "hermes-webui-start" ''
        cd /data/projects/own/hermes-webui
        export HERMES_WEBUI_PASSWORD=$(cat $CREDENTIALS_DIRECTORY/hermes-webui-password)
        exec "${hermesVenv}/bin/python" server.py
      '';
      ExecStartPost = pkgs.writeShellScript "hermes-webui-warmup" ''
        # Pre-warm agent init so first user chat isn't slow
        sleep 3
        curl -sf http://127.0.0.1:8787/health >/dev/null 2>&1 && echo "[webui] warmup ok" || true
        exit 0
      '';
      Restart = "always";
      RestartSec = 5;
      User = "j_kro";
      Group = "users";
      WorkingDirectory = "/data/projects/own/hermes-webui";
    };
  };

  # Auto-update hermes-webui repo daily
  systemd.timers.hermes-webui-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
  systemd.services.hermes-webui-update = {
    description = "Pull hermes-webui updates";
    serviceConfig = {
      Type = "oneshot";
      User = "j_kro";
      ExecStart = pkgs.writeShellScript "hermes-webui-update" ''
        cd /data/projects/own/hermes-webui
        git pull --ff-only 2>/dev/null && echo "[webui] updated" || echo "[webui] no updates or error"
      '';
    };
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
      GLM_BASE_URL=https://api.z.ai/api/coding/paas/v4
      ENVEOF
      echo -n "API_SERVER_KEY=" >> /data/hermes/.hermes/provider-env
      cat /run/agenix/hermes-api-server-key >> /data/hermes/.hermes/provider-env
      echo -n "ZAI_API_KEY="" " >> /data/hermes/.hermes/provider-env
      cat /run/agenix/zai-api-key >> /data/hermes/.hermes/provider-env
      echo "" >> /data/hermes/.hermes/provider-env
      echo -n "NVIDIA_API_KEY=" >> /data/hermes/.hermes/provider-env
      cat /run/agenix/nvidia-api-key >> /data/hermes/.hermes/provider-env
      chmod 600 /data/hermes/.hermes/provider-env
      chown j_kro:users /data/hermes/.hermes/provider-env
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

  # Cluster service registry — single source of truth for DNS + Caddy
  # All .lan domains terminate TLS on nexus and proxy to backends
  # Uses K8s service DNS (stable across recreations) instead of ephemeral ClusterIPs
  services.cluster-services = {
    enable = true;
    services = {
      searxng = {
        domain = "searxng.lan";
        backend = k8s.searxng.dns;
      };
      search = {
        domain = "search.lan";
        backend = k8s.vane.dns;
        compress = false;
      };
      ai = {
        domain = "ai.lan";
        backend = "127.0.0.1:8080";
      };
      openwebui = {
        domain = "openwebui.lan";
        backend = k8s.open-webui.dns;
      };
      haven = {
        domain = "haven.lan";
        backend = k8s.haven.dns;
      };
      hermes = {
        domain = "hermes.lan";
        backend = "127.0.0.1:8787";
      };
      api-hermes = {
        domain = "api.hermes.lan";
        backend = "127.0.0.1:8642";
      };
      n8n = {
        domain = "n8n.lan";
        backend = k8s.n8n.dns;
      };
      activepieces = {
        domain = "activepieces.lan";
        backend = k8s.activepieces.dns;
      };
      ai-inference = {
        domain = "ai-inference.lan";
        backend = k8s.ai-gateway.dns;
      };
      qdrant = {
        domain = "qdrant.lan";
        backend = k8s.qdrant.dns;
      };
      knowledge-fabric = {
        domain = "knowledge-fabric.lan";
        backend = k8s.knowledge-fabric.dns;
      };
    };
  };
}

