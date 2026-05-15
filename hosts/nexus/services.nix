{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  ports = import ../../kubernetes/service-ports.nix;

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
      clusterInit = false; # Rejoining existing cluster, not bootstrapping
      nodeName = "nexus";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = cluster.hosts.nexus.ip;
    };

    keepalived-vip = {
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 110;
    };

    gaming-detection.enable = lib.mkForce false;

    nexus-exec.enable = true;

    nixos-share = {
      enable = true;
      client.enable = true;
    };

    nfs-data-server.enable = true;

    agenix-secrets-registry = {
      enable = true;
      aiServices = true;
      monitoring = false;
      storage = true;
      mining = false;
      cloud = false;
      kubernetes = true;
      initrdRecovery = true;
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
    addToSystemPackages = false; # hermes-with-whatsapp (superset) added via hermes-cli.nix

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
          base_url = "http://llama-server-zephyr.ai-inference.svc.cluster.local:1237/v1";
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
      toolsets = ["all"];
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

    # Secrets loaded via ExecStartPre + EnvironmentFile override below
    mcpServers = {
      github = {
        command = "npx";
        args = ["-y" "@modelcontextprotocol/server-github"];
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

    extraPackages = with pkgs; [git ripgrep curl jq];
  };

  # Hermes WebUI — disabled on nexus (no /data/projects/own/hermes-webui)
  # Runs on zephyr only. Dead code and timer removed.

  # Load Z.AI and NVIDIA API keys for hermes-agent
  # The official module's environment option doesn't reliably set systemd env vars,
  # so we use a systemd override with ExecStartPre to generate an env file.
  systemd.services.hermes-agent = {
    serviceConfig.ExecStartPre =
      "+"
      + (pkgs.writeShellScript "hermes-load-env" ''
        mkdir -p /data/hermes/.hermes
        cat > /data/hermes/.hermes/provider-env << 'ENVEOF'
        API_SERVER_ENABLED=true
        API_SERVER_HOST=0.0.0.0
        API_SERVER_PORT=8642
        GLM_BASE_URL=https://api.z.ai/api/coding/paas/v4
        ENVEOF
        echo -n "API_SERVER_KEY=" >> /data/hermes/.hermes/provider-env
        cat /run/agenix/hermes-api-server-key >> /data/hermes/.hermes/provider-env
        # TODO: agenix - populate before deploy
        echo -n "ZAI_API_KEY=" >> /data/hermes/.hermes/provider-env
        cat /run/agenix/zai-api-key >> /data/hermes/.hermes/provider-env
        echo "" >> /data/hermes/.hermes/provider-env
        # TODO: agenix - populate before deploy
        echo -n "NVIDIA_API_KEY=" >> /data/hermes/.hermes/provider-env
        cat /run/agenix/nvidia-api-key >> /data/hermes/.hermes/provider-env
        chmod 600 /data/hermes/.hermes/provider-env
        chown j_kro:users /data/hermes/.hermes/provider-env
      '');
    # Use "-" prefix so systemd doesn't fail if file doesn't exist yet
    serviceConfig.EnvironmentFile = "-/data/hermes/.hermes/provider-env";
  };

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
        backend = "127.0.0.1:8642";
      };
      api-hermes = {
        domain = "api.hermes.lan";
        backend = "127.0.0.1:8642";
      };
      n8n = {
        domain = "n8n.lan";
        backend = k8s.n8n.dns;
      };
      auth = {
        domain = "auth.lan";
        backend = k8s.casdoor.dns;
      };

      ai-inference = {
        domain = "ai-inference.lan";
        backend = "ai-inference-gateway.ai-inference.svc.cluster.local:8080";
      };
      qdrant = {
        domain = "qdrant.lan";
        backend = k8s.qdrant.dns;
      };
      maplespike-api = {
        domain = "maplespike-api.lan";
        backend = "127.0.0.1:${toString ports.maplespike-api}";
      };
      maplespike-mcp = {
        domain = "maplespike-mcp.lan";
        backend = "127.0.0.1:${toString ports.maplespike-mcp}";
      };
      maplespike-status = {
        domain = "status.maplespike.lan";
        backend = "127.0.0.1:${toString ports.maplespike-status}";
      };
      maplespike = {
        domain = "maplespike.lan";
        backend = "127.0.0.1:${toString ports.maplespike-portal}";
        rawBlock = ''
          https://maplespike.lan {
            tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key
            encode zstd gzip
            handle /api/v1/* {
              reverse_proxy 127.0.0.1:${toString ports.maplespike-api}
            }
            handle /sse {
              reverse_proxy 127.0.0.1:${toString ports.maplespike-mcp}
            }
            handle /messages {
              reverse_proxy 127.0.0.1:${toString ports.maplespike-mcp}
            }
            handle /health {
              reverse_proxy 127.0.0.1:${toString ports.maplespike-mcp}
            }
            handle {
              reverse_proxy 127.0.0.1:${toString ports.maplespike-portal}
            }
          }
        '';
      };
      dev-maplespike-api = {
        domain = "dev-maplespike-api.lan";
        backend = "127.0.0.1:${toString ports.dev-maplespike-api}";
      };
      dev-maplespike-mcp = {
        domain = "dev-maplespike-mcp.lan";
        backend = "127.0.0.1:${toString ports.dev-maplespike-mcp}";
      };
      dev-maplespike = {
        domain = "dev.maplespike.lan";
        backend = "127.0.0.1:${toString ports.dev-maplespike-portal}";
      };
    };
  };
  # Initrd SSH recovery + BTRFS snapshots
  services.initrd-ssh-recovery = {
    enable = true;
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = true;
  services.btrfs-boot-snapshot = {
    enable = true;
    subvolume = "@root";
    device = "/dev/disk/by-uuid/076e60fb-09b9-4f5c-9d9b-cdbb1f1f859b";
  };
}