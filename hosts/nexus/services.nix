{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  portHelpers = import ../../modules/port-helpers.nix {inherit lib;};
  ports = portHelpers.ports;

  # Build the hermes-agent Python venv (same derivation the flake uses for its wrappers)
  hermesVenv = pkgs.callPackage (inputs.hermes-agent.outPath + "/nix/python.nix") {
    inherit (inputs.hermes-agent.inputs) uv2nix pyproject-nix pyproject-build-systems;
  };
  k8s = config.networking.cluster.kubernetes.services;
  cluster = config.networking.cluster;
in {
  systemd.tmpfiles.rules = [
    "R /var/lib/etcd - - - - -"
    "d /data/hermes 0775 j_kro j_kro -"
    "d /data/pi 0775 j_kro j_kro -"
  ];

  services = {
    hermes-cli = {
      enable = true;
      apiKeyFile = config.age.secrets.zai-api-key.path;
      nvidiaApiKeyFile = config.age.secrets.nvidia-api-key.path;
      casdoorJwtFile = config.age.secrets.casdoor-hermes-jwt.path;
      opencodeGoApiKeyFile = config.age.secrets.opencode-go-api-key.path;
    };
    k3s-cluster = {
      enable = false;  # Temporarily disabled to unblock rebuild
      nvidia.enable = true;
      role = "server";
      clusterInit = false; # Rejoining existing cluster via VIP (fixed 2026-05-30)
      clusterReset = false; # Already reset, running clean
      nodeName = "nexus";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = cluster.hosts.nexus.ip;
      flannelIface = "eth0"; # Nexus primary interface (eth0 has NO-CARRIER)
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
      enable = false;
      client.enable = true;
    };

    nfs-data-server = {
      enable = true;
      exports = ''
        /data/hermes 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=105)

        /data/pi 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=106)
      '';
    };

    agenix-secrets-registry = {
      enable = true;
      aiServices = true;
      monitoring = false;
      storage = true;
      mining = false;
      cloud = false;
      kubernetes = true;
      initrdRecovery = false; # Disabled: agenix build-time dependency issue
      selfHosting = false;
    };

    nfs-state-sync = {
      enable = false;
      sourceHost = "zephyr";
      paths = ["/data/hermes" "/data/pi"];
      interval = "15min";
    };

    # Local nix binary cache for cluster (serves built closures to all hosts)
    binary-cache.enable = true;
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
          model = "Carnice-Qwen3.6-MoE-35B-A3B.IQ4_XS.gguf";
        };
        llama-cpp-sentry = {
          base_url = "http://llama-server-sentry.ai-inference.svc.cluster.local:1235/v1";
          api_key = "unused";
          model = "Qwen3.5-4B-Q4_K_M.gguf";
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
          model = "Qwen3.5-4B-Q4_K_M.gguf";
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

    extraPackages = with pkgs; [git ripgrep curl jq statix deadnix osv-scanner];
  };

  # Hermes WebUI — disabled on nexus (no /data/projects/own/hermes-webui)
  # Runs on zephyr only. Dead code and timer removed.

  # Agent network restrictions — restrict AI agents to allowed destinations only
  services.agent-firewall = {
    enable = false;  # Disabled - broken module drops all traffic
    auditLog = true;
  };

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
        echo "" >> /data/hermes/.hermes/provider-env
        # TODO: agenix - populate before deploy
        echo -n "ZAI_API_KEY=" >> /data/hermes/.hermes/provider-env
        cat /run/agenix/zai-api-key >> /data/hermes/.hermes/provider-env
        echo "" >> /data/hermes/.hermes/provider-env
        # TODO: agenix - populate before deploy
        echo -n "NVIDIA_API_KEY=" >> /data/hermes/.hermes/provider-env
        cat /run/agenix/nvidia-api-key >> /data/hermes/.hermes/provider-env
        echo "" >> /data/hermes/.hermes/provider-env
        chmod 600 /data/hermes/.hermes/provider-env
        chown hermes:hermes /data/hermes/.hermes/provider-env
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
      openwebui = {
        domain = "openwebui.lan";
        backend = k8s.open-webui.dns;
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
      ai-inference = {
        domain = "ai-inference.lan";
        backend = "ai-inference-gateway.ai-inference.svc.cluster.local:8080";
      };
      qdrant = {
        domain = "qdrant.lan";
        backend = k8s.qdrant.dns;
      };
      maplespike-api = {
        domain = "api.maplespike.lan";
        backend = "127.0.0.1:${toString ports.maplespike-api}";
      };
      maplespike-mcp = {
        domain = "mcp.maplespike.lan";
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
        domain = "dev-api.maplespike.lan";
        backend = "10.1.1.120:${toString ports.dev-maplespike-api}";
      };
      dev-maplespike-mcp = {
        domain = "dev-mcp.maplespike.lan";
        backend = "10.1.1.120:${toString ports.dev-maplespike-mcp}";
      };
      dev-maplespike = {
        domain = "dev.maplespike.lan";
        backend = "10.1.1.120:${toString ports.dev-maplespike-portal}";
      };
    };
  };
  # Initrd SSH recovery + BTRFS snapshots
  services.initrd-ssh-recovery = {
    enable = true; # Fixed: key generated at build time
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.cluster-mesh.enable = true; # SSH service account for inter-node mesh
  services.recovery-specialisation.enable = true; # depends on initrd-ssh
  services.btrfs-boot-snapshot = {
    enable = true; # depends on initrd-ssh
    subvolume = "@root";
    device = "/dev/disk/by-uuid/076e60fb-09b9-4f5c-9d9b-cdbb1f1f859b";
  };

  services.cachix-auth.enable = true;

  # GitHub Actions self-hosted runner on nexus (official binary)
  systemd.services.github-actions-runner = {
    description = "GitHub Actions Runner";
    after = ["network.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "simple";
      User = "j_kro";
      WorkingDirectory = "/home/j_kro/actions-runner-official";
        Environment = [
          "DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1"
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin:${lib.makeBinPath [pkgs.coreutils pkgs.gnutar pkgs.gzip pkgs.git pkgs.bash pkgs.gnugrep pkgs.findutils pkgs.curl pkgs.openssl]}"
          "LD_LIBRARY_PATH=${lib.makeLibraryPath [pkgs.icu]}"
          "NIX_ICU_DATA=${pkgs.icu}/share/icu/${pkgs.icu.version}"
          "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          "REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt"
          "NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-bundle.crt"
        ];
      ExecStart = "/home/j_kro/actions-runner-official/start-runner.sh";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "180s";
    };
  };

  services.ai-coding-tools = {
    enable = true;
    user = "j_kro";
    zaiApiKeyFile = config.age.secrets.zai-api-key.path;
    context7ApiKeyFile = config.age.secrets.context7-api-key.path;
    nvidiaNimApiKeyFile = config.age.secrets.nvidia-api-key.path;
    opencodeGoApiKeyFile = config.age.secrets.opencode-go-api-key.path;
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

  services.mcp-registry = {
    enable = true;
    generateHermes = true;
    generateClaudeCode = true;
    generateKagentCRDs = true;
    generateNetworkPolicies = true;
    generateCasdoorApps = true;
  };
}
