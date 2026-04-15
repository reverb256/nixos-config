{ config, pkgs, lib, inputs, ... }:
{
  systemd.tmpfiles.rules = [
    "R /var/lib/etcd - - - - -"
  ];

  services = {
    k3s-cluster = {
      enable = false; # NixOS module not available yet
      nvidia.enable = false; # NixOS module not available yet
      role = "server";
      clusterInit = true;
      nodeName = "nexus";
      serverAddr = "https://10.1.1.100:6443";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = "10.1.1.120";
      calico.enable = false; # NixOS module not available yet
    };

    keepalived-vip = {
      enable = false; # NixOS module not available yet
      vip = "10.1.1.100";
      interface = "enp7s0";
      priority = 100;
    };

    gaming-detection.enable = lib.mkForce false;
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
      enable = false; # NixOS module not available yet
      client.enable = false; # NixOS module not available yet
    };

    nfs.server.enable = false; # NixOS module not available yet

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
      rpcSecret = "b048d5cc40c1ccbdc9232c3830fbf0a47257c1f68b1debfadab4e6d93c38165a";
    };

    status-auto-update.enable = false; # NixOS module not available yet

    unbound-common.enable = false; # NixOS module not available yet

    ai-coding-tools = {
      enable = false; # NixOS module not available yet
      zaiApiKeyFile = config.age.secrets.zai-api-key.path;
      context7ApiKeyFile = "/run/agenix/context7-api-key";
    };

    agenix-secrets-registry = {
      enable = false; # NixOS module not available yet
      aiServices = true;
      mining = true;
      storage = true;
      kubernetes = true;
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
      model = {
        provider = "zai";
        default = "glm-5.1";
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
        threshold = 0.85;
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
    enable = true;
    port = 9119;
    host = "0.0.0.0";
    openFirewall = true;
  };

  # Load Z.AI API key and configure hermes-agent environment
  # The official module's environment option doesn't reliably set systemd env vars,
  # so we use a systemd override with ExecStartPre to generate an env file.
  systemd.services.hermes-agent = {
    serviceConfig.ExecStartPre = "+" + (pkgs.writeShellScript "hermes-load-env" ''
      mkdir -p /var/lib/hermes/.hermes
      cat > /var/lib/hermes/.hermes/provider-env << 'ENVEOF'
      API_SERVER_ENABLED=true
      API_SERVER_HOST=0.0.0.0
      API_SERVER_PORT=8642
      API_SERVER_KEY=hermes-local-dev-b8b2275d6053fb335a9508048c54dc96
      GLM_BASE_URL=https://api.z.ai/api/coding/paas/v4
      ENVEOF
      echo -n "ZAI_API_KEY=" >> /var/lib/hermes/.hermes/provider-env
      cat /run/agenix/zai-api-key >> /var/lib/hermes/.hermes/provider-env
      chmod 600 /var/lib/hermes/.hermes/provider-env
      chown hermes:hermes /var/lib/hermes/.hermes/provider-env
    '');
    # Use "-" prefix so systemd doesn't fail if file doesn't exist yet
    serviceConfig.EnvironmentFile = "-/var/lib/hermes/.hermes/provider-env";
  };

  # Knowledge Base MCP server — RAG search over 38 ingested books
  systemd.services.kb-mcp-server = {
    description = "Knowledge Base RAG MCP Server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = with pkgs; [ python3 gcc.cc ];
    environment = {
      QDRANT_HOST = "127.0.0.1";
      QDRANT_PORT = "6333";
      KB_PORT = "8643";
      KB_HOST = "0.0.0.0";
      PYTHONPATH = "src";
      LD_LIBRARY_PATH = "${pkgs.gcc.cc.lib}/lib";
    };
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "/data/projects/infra/knowledge-base";
      ExecStart = "/data/projects/infra/knowledge-base/.venv/bin/python -m kb_mcp.server";
      Restart = "on-failure";
      RestartSec = 5;
      User = "j_kro";
    };
  };

  # Brain wiki sync from zephyr → nexus (for gateway knowledge fabric)
  # DEPRECATED: Wiki pages are display-only. Qdrant is the retrieval path.
  # Disabled — brain-wiki Qdrant collection is updated directly via embed endpoint.
  systemd.services.brain-wiki-sync = {
    description = "Sync brain wiki from zephyr";
    path = with pkgs; [ rsync openssh ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "brain-wiki-sync" ''
        mkdir -p /home/j_kro/brain/wiki
        ${pkgs.rsync}/bin/rsync -az --delete j_kro@10.1.1.110:/home/j_kro/brain/wiki/ /home/j_kro/brain/wiki/
      '';
      User = "j_kro";
    };
  };

  systemd.timers.brain-wiki-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    enable = false;  # Disabled: wiki pages are display-only
  };

  users.users.j_kro.extraGroups = [
    "plugdev"
    "audio"
    "input"
    "docker"
    "openrazer"
    "tailscale"
    "video"
    "render"
  ];
}
