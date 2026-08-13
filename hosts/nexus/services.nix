{
  config,
  pkgs,
  lib,
  ...
}: let
  portHelpers = import ../../modules/port-helpers.nix {inherit lib;};
  inherit (portHelpers) ports;

  cluster = config.networking.cluster;
in {
  systemd.tmpfiles.rules = [
    "R /var/lib/etcd - - - - -"
    "d /data/hermes 0775 j_kro j_kro -"
    "d /data/pi 0775 j_kro j_kro -"
  ];

  services = {
    # k3s-cluster config is in configuration.nix (canonical host config)

    keepalived-vip = {
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 110;
    };

    nexus-exec.enable = true;
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

  # Hermes Agent — REMOVED from nixos-config (issue #334).
  # Hermes is now provided by the user nix profile
  # (`nix profile install github:NousResearch/hermes-agent`); nixos-config no
  # longer builds or runs the hermes-agent daemon. The Caddy routes
  # hermes.lan / api.hermes.lan (→ :8642) will 502 until a profile-managed
  # service is stood up if needed. Interactive use is via the profile binary.

  # Hermes WebUI — disabled on nexus (no /data/projects/own/hermes-webui)
  # Runs on zephyr only. Dead code and timer removed.

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

  # Cluster service registry — single source of truth for DNS + Caddy
  # All .lan domains terminate TLS on nexus and proxy to backends
  # Uses K8s service DNS (stable across recreations) instead of ephemeral ClusterIPs
  services.cluster-services = {
    enable = true;
    services = {
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
  services.recovery-specialisation.enable = true; # depends on initrd-ssh

  services.ai-coding-tools = {
    enable = true;
    user = "j_kro";
    zaiApiKeyFile = "/run/secrets/zai-api-key";
    context7ApiKeyFile = "/run/secrets/context7-api-key";
    nvidiaNimApiKeyFile = "/run/secrets/nvidia-api-key";
    tools = {
      claude = {enable = true;};
      opencode = {enable = true;};
      droid = {enable = true;};
      crush = {enable = true;};
      pi = {enable = true;};
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
    # 2026-08-11: was tokenFile, which passed the raw PAT straight to
    # config.sh --token -> GitHub 404 ("Bad credentials" on registration).
    # patFile makes the setup script exchange the PAT for a fresh
    # registration token via POST /actions/runners/registration-token
    # (verified: HTTP 201 + "√ Successfully replaced the runner").
    patFile = "/run/secrets/github-runner-pat";
    autoStart = true;
    # Issue #474: pin trusted CI jobs to the Nexus builder explicitly.
    # Heavy workflows require [self-hosted, nixos, nexus, builder]; a job
    # never lands on an unlabelled runner by accident.
    extraLabels = ["nexus" "builder"];
  };

  services.k8s-secret-sync = {
    enable = true;
    # MapleSpike/Quill Stripe + JWT secret mappings removed 2026-08-08: the
    # maplespike/billing.yaml + runtime.yaml secret files were never committed
    # to the repo, which kept secretspec-creds failing as a unit (and would
    # block the cluster-CA provisioning that requires its success). Re-add
    # here + in secretspec-creds-wiring.nix once the real secrets are committed
    # under /etc/nixos/secrets/maplespike/.
  };
  # Use local kubeconfig instead of cluster join token (node token is not a valid API bearer token)
  services.k8s-nix-deploy.tokenFile = lib.mkForce null;
}
