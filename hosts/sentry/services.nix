{
  config,
  lib,
  pkgs,
  inputs, ...
}: let
  cluster = config.networking.cluster;
in {
  services = {
    k3s-cluster = {
      enable = true;
      role = "server";
      nodeName = "sentry";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = cluster.hosts.sentry.ip;
    };

    keepalived-vip = {
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 100;
    };

    gaming-detection.enable = true;
    gpu-profile-manager.enable = true;
    mining-coordinator.enable = true;

    nginx = {
      enable = false;
      recommendedProxySettings = true;
      recommendedGzipSettings = true;
      virtualHosts."_" = {
        default = true;
        locations."= /".return = "200 'OK'";
        locations."= /".extraConfig = ''
          add_header Content-Type text/plain;
        '';
      };
    };

    spotify-spotx.enable = lib.mkDefault true;

    tailscale.enable = true;

    nixos-share = {
      enable = true;
      client.enable = true;
    };

    nfs-client = {
      enable = true;
      mountShared = true;
      mountHome = false;
      mountMedia = false;
    };

    # Secondary NFS data server for failover (hermes + pi state)
    nfs-data-server = {
      enable = true;
      exports = ''
        /data/hermes 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=105)

        /data/pi 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=106)
      '';
    };
    nfs-state-sync = {
      enable = true;
      sourceHost = "nexus";
    };

    syncthing-cluster = {
      enable = true;
    };

  };

  services.cluster-mesh.enable = true; # SSH service account for inter-node mesh
  # Create directories for hermes/pi bind mounts on Sentry
  systemd.tmpfiles.rules = [
    "d /data/hermes 0775 j_kro j_kro -"
    "d /data/pi 0775 j_kro j_kro -"
  ];

  # Cluster DNS configuration
  networking.cluster.dns.enable = true;

  services.xserver.videoDrivers = ["amdgpu"];

  systemd.services.ai-inference-monitor = {
    wantedBy = lib.mkForce [];
    enable = true;
  };

  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # Initrd SSH recovery + BTRFS snapshots
  services.cluster-ca = {
    enable = true;
    generateLeaf = true;
  };

  services.initrd-ssh-recovery = {
    enable = true;
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = true;
  services.btrfs-boot-snapshot.enable = lib.mkForce false;

  services.cachix-auth.enable = true;
  services.ai-coding-tools = {
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

  services.ci-runner = {
    enable = true;
    repo = "reverb256/nixos-config";
    tokenFile = "/run/secrets/github-runner-pat";
    autoStart = true;
    extraLabels = ["sentry"];
  };

  # Caddy reverse proxy — same routes as Nexus for HA
  services.cluster-services = {
    enable = true;
    services = {
      vaultwarden = {
        domain = "vaultwarden.lan";
        backend = "vaultwarden.vaultwarden.svc.cluster.local:8080";
      };
      glance = {
        domain = "dashboard.lan";
        backend = "glance.dashboard.svc.cluster.local:8080";
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
}

