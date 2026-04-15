{ config, pkgs, lib, inputs, ... }:
{
  systemd.tmpfiles.rules = [
    "R /var/lib/etcd - - - - -"
  ];

  services = {
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      clusterInit = true;
      nodeName = "nexus";
      serverAddr = "https://10.1.1.100:6443";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = "10.1.1.120";
      calico.enable = true;
    };

    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "enp7s0";
      priority = 100;
    };

    gaming-detection.enable = true;
    gpu-profile-manager.enable = true;
    mining-coordinator.enable = true;

    garnix.enable = true;
    nixos-auto-update.enable = true;

    spotify-spotx.enable = true;

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
          enable = true;
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
      enable = true;
      servers.playwright.enable = true;
      servers.context7.apiKeyFile = "/run/agenix/context7-api-key";
    };

    nixos-share = {
      enable = true;
      client.enable = true;
    };

    nfs.server.enable = true;

    syncthing-cluster = {
      enable = true;
      deviceId = "NEXUS-PLACEHOLDER";
    };

    garage-cluster = {
      enable = true;
      dataDir = "/data/shared/garage";
      replicationFactor = 1;
      consistencyMode = "consistent";
      enableMetrics = true;
      enableBackup = false;
      rpcSecret = "b048d5cc40c1ccbdc9232c3830fbf0a47257c1f68b1debfadab4e6d93c38165a";
    };

    host-dashboard = {
      enable = true;
      role = "control-plane + storage + gaming";
      port = 8090;
      prometheusUrl = "http://127.0.0.1:9090";
      featuredServices = [
        {
          name = "Prometheus";
          url = "http://127.0.0.1:9090";
        }
        {
          name = "Grafana";
          url = "http://127.0.0.1:3000";
        }
      ];
      services = [
        {
          name = "kubelet";
          active = true;
        }
        {
          name = "containerd";
          active = true;
        }
        {
          name = "cfssl";
          active = true;
        }
        {
          name = "keepalived";
          active = true;
        }
        {
          name = "NFS Server";
          active = true;
        }
      ];
    };

    status-auto-update.enable = true;

    unbound-common.enable = true;

    ai-coding-tools = {
      enable = true;
      zaiApiKeyFile = config.age.secrets.zai-api-key.path;
      context7ApiKeyFile = "/run/agenix/context7-api-key";
    };

    agenix-secrets-registry = {
      enable = true;
      aiServices = true;
      mining = true;
      storage = true;
      kubernetes = true;
    };
  };

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
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
        default = "gemma-4-e4b-it";  # matches our local model
        base_url = "http://127.0.0.1:8080/v1";  # AI gateway on nexus
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

    # Non-secret environment vars
    environment = {
      API_SERVER_ENABLED = "true";
      API_SERVER_PORT = "8642";
      API_SERVER_HOST = "0.0.0.0";  # accessible from LAN
    };

    # Secrets (via agenix)
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
