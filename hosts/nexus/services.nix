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
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      clusterInit = false; # Stable cluster running
  clusterReset = false; # Already reset, running clean
      nodeName = "nexus";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/persistent/etc/k3s-cluster-token";
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
      enable = true;
      client.enable = true;
    };

    nfs-data-server = {
      enable = true;
      exports = ''
        /data/hermes 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=105)

        /data/pi 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=106)
      '';
    };


    nfs-state-sync = {
      enable = true;
      sourceHost = "zephyr";
      paths = ["/data/hermes" "/data/pi"];
      interval = "15min";
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

    extraPackages = with pkgs; [git ripgrep curl jq];
  };

   # Hermes WebUI — disabled on nexus (no /data/projects/own/hermes-webui)
   # Runs on zephyr only. Dead code and timer removed.


  # Load Z.AI and NVIDIA API keys for hermes-agent
  # The official module's environment option doesn't reliably set systemd env vars,
  # so we use a systemd override with ExecStartPre to generate an env file.

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
        backend = "127.0.0.1:32081";
      };
      search = {
        domain = "search.lan";
        backend = "127.0.0.1:30900";
        compress = false;
      };
      openwebui = {
        domain = "openwebui.lan";
        backend = "127.0.0.1:32080";

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
        backend = "127.0.0.1:32127";
      };
      ai-inference = {
        domain = "ai-inference.lan";
        backend = "ai-inference-gateway.ai-inference.svc.cluster.local:8080";
      };
      qdrant = {
        domain = "qdrant.lan";
        backend = "127.0.0.1:30632";
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
      vaultwarden = {
        domain = "vaultwarden.lan";
        backend = "vaultwarden.vaultwarden.svc.cluster.local:8080";
      };
      glance = {
        domain = "dashboard.lan";
        backend = "127.0.0.1:32200";
      };
      grafana = {
        domain = "grafana.lan";
        backend = "grafana.monitoring.svc.cluster.local:3000";
        protected = true;
      };
      gitea = {
        domain = "gitea.lan";
        backend = "gitea.ai-inference.svc.cluster.local:3000";
      };
      privacy-filter = {
        domain = "privacy-filter.lan";
        backend = "privacy-filter.search.svc.cluster.local:8080";
      };
      mission-control = {
        domain = "mission-control.lan";
        backend = "mission-control.orchestration.svc.cluster.local:8080";
        protected = true;
      };
      removed = {
        domain = "removed.lan";
        backend = "removed-ui.removed.svc.cluster.local:8080";
      };
      workspace = {
        domain = "workspace.lan";
        backend = "127.0.0.1:3002";
      };
      auth = {
        domain = "auth.lan";
        backend = "127.0.0.1:32556";
        rawBlock = ''
          https://auth.lan {
            tls /etc/ssl/cluster-ca/leaf.crt /etc/ssl/cluster-ca/leaf.key
            encode zstd gzip
            rate_limit {
              zone auth_per_ip {
                key    {remote_host}
                events 100
                window 1m
              }
            }
            handle /oauth2/* {
              reverse_proxy 127.0.0.1:30890
            }
            handle {
              reverse_proxy 127.0.0.1:32556
            }
          }
        '';
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
  services.lpminer = {
    enable = lib.mkForce false;
  };
  services.cluster-mesh.enable = true; # SSH service account for inter-node mesh
  services.recovery-specialisation.enable = true; # depends on initrd-ssh
  services.btrfs-boot-snapshot.enable = lib.mkForce false; # NixOS generations sufficient

  services.cachix-auth.enable = true;
   services.ai-coding-tools = {
     enable = true;
     user = "j_kro";
     zaiApiKeyFile = "/run/secrets/zai-api-key";
     context7ApiKeyFile = "/run/secrets/context7-api-key";
     nvidiaNimApiKeyFile = "/run/secrets/nvidia-api-key";
     opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
     tools = {
       claude = { enable = true; };
       opencode = { enable = true; };
       droid = { enable = true; };
       crush = { enable = true; };
       pi = { enable = true; };
       omp = { enable = true; };
     };
     enableShellEnv = true;
   };

   services.mcp-registry = {
     enable = true;
     generateHermes = true;
     generateClaudeCode = true;
     generateNetworkPolicies = true;
     generateCasdoorApps = true;
   };

  # GitHub Actions self-hosted runner for CI/CD
  services.ci-runner = {
    enable = true;
    repo = "reverb256/nixos-config";
    tokenFile = "/run/secrets/github-runner-pat";
    autoStart = true;
    extraLabels = ["nexus"];
  };

  services.k8s-secret-sync = {
    enable = true;
  };
}