# Nexus Service Configuration
# K3s control plane (bootstrap node), NFS server, Garage S3,
# monitoring stack, Steam gaming, mining configuration
{ config, pkgs, lib, inputs, ... }:
{
  # Clean old etcd data directory (standalone etcd removed)
  systemd.tmpfiles.rules = [
    "R /var/lib/etcd - - - - -"
  ];

  services = {
    # KUBERNETES - k3s control plane (cluster bootstrap node)
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

    # Keepalived VIP for HA API server access
    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "enp7s0";
      priority = 100;
    };

    # Modular workload monitoring
    gaming-detection.enable = true;
    gpu-profile-manager.enable = true;
    mining-coordinator.enable = true;

    garnix.enable = true;
    nixos-auto-update.enable = true;

    # Spotify with SpotX patch
    spotify-spotx.enable = true;

    # Mining configuration
    mining = {
      # CPU mining DISABLED - K8s version working instead
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

      # GPU mining DISABLED on nexus - runs via Kubernetes
      lolminer.nvidia = {
        enable = false;
        powerLimit = 120; # RTX 3060 Ti @ 120W
      };
    };

    # MCP servers
    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
    };

    # Mount /etc/nixos from zephyr
    nixos-share = {
      enable = true;
      client.enable = true;
    };

    # NFS Server - Export shared storage for cluster
    nfs.server.enable = true;

    # Syncthing P2P file sync
    syncthing-cluster = {
      enable = true;
      deviceId = "NEXUS-PLACEHOLDER";
    };

    # Garage S3-compatible object storage (single-node cluster)
    garage-cluster = {
      enable = true;
      dataDir = "/data/shared/garage";
      replicationFactor = 1;
      consistencyMode = "consistent";
      enableMetrics = true;
      enableBackup = false;
      rpcSecret = "b048d5cc40c1ccbdc9232c3830fbf0a47257c1f68b1debfadab4e6d93c38165a";
    };

    # Host Dashboard
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

    # STATUS.md auto-update
    status-auto-update.enable = true;

    # Unbound DNS
    unbound-common.enable = true;

    # Agenix secrets
    agenix-secrets-registry = {
      enable = true;
      aiServices = true;
      mining = true;
      storage = true;
      kubernetes = true;
    };
  };

  # ============================================================================
  # STEAM - Gamescope session alongside Plasma
  # ============================================================================
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
  };

  # ============================================================================
  # PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # opencode now via home-manager
    llama-cpp
  ];

  # ============================================================================
  # TAILSCALE - Nexus does not advertise routes
  # ============================================================================
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # ============================================================================
  # USER GROUPS
  # ============================================================================
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
