{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cluster = config.networking.cluster;
  # Multi-repo runner generator (2026-08-13 pattern from nexus). Sentry runs
  # the site-agency pipeline (its deploy target), so its CI runner must live
  # HERE, not on nexus/zephyr — jobs tagged [self-hosted, nixos, gpu] for
  # reverb256/site-agency register against this host's runner.
  ciRunners = import ../../modules/services/ci-runners.nix {inherit lib pkgs;};
  runnerFragments = ciRunners {
    instances = {
      nixos-config = {
        user = "runner";
        repo = "reverb256/nixos-config";
        patFile = "/run/secrets/github-runner-pat";
        autoStart = true;
        labels = ["self-hosted" "nixos"];
        extraLabels = ["sentry" "builder"];
        runnerName = "sentry-runner";
        memoryHigh = "8G";
        memoryMax = "12G";
      };
      site-agency = {
        user = "runner";
        repo = "reverb256/site-agency";
        patFile = "/run/secrets/github-runner-pat";
        autoStart = true;
        labels = ["self-hosted" "nixos" "gpu"];
        extraLabels = ["sentry" "site-agency"];
        runnerName = "sentry-site-agency-runner";
        # site-agency CI (lint/security/deploy) is light: venv + ruff +
        # pytest + rsync-to-self. No nix builds. Keep it small.
        memoryHigh = "4G";
        memoryMax = "8G";
      };
    };
  };
in {
  config = lib.mkMerge [
    runnerFragments
    {
      services = {
        hermes-cli = {
          enable = true;
          nvidiaApiKeyFile = "/run/secrets/nvidia-api-key";
          opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
          opencodeZenApiKeyFile = "/run/secrets/opencode-api-key";
        };
        k3s-cluster = {
          enable = true;
          role = "agent";
          # 2026-07-28: mkForce false. The `true` here was a stale leftover from
          # initial bootstrap; on a healthy control-plane node the etcd state at
          # /var/lib/rancher/k3s/server/db is the canonical cluster truth and must
          # NOT be wiped on every activation — that path requires an explicit
          # one-shot rescue (`services.k3s-cluster.wipeState` or wipeState=true).
          etcdClean = lib.mkForce false;
          nodeName = "sentry";
          serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
          tokenFile = "/run/secrets/k3s-cluster-token";
          nodeIP = cluster.hosts.sentry.ip;
          secretsEncryptionKeyFile = "/run/secrets/k3s-encryption-key";
        };

        keepalived-vip = {
          enable = true;
          vip = cluster.kubernetes.vip;
          interface = "enp7s0";
          priority = 100;
        };

        gaming-detection.enable = false;
        gpu-profile-manager.enable = false;
        mining-coordinator.enable = false;

        nginx = {
          enable = true;
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

        sops-secrets-registry = {
          enable = true;
          kubernetes = true;
          aiServices = true;
          ci = true;
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
        enable = false;
      };

      systemd.services.tailscaled.environment = {
        TS_ADVERTISE_ROUTES = "10.1.1.0/24";
        TS_ROUTES = "";
        TS_SSH = "true";
      };

      # Initrd SSH recovery + BTRFS snapshots
      services.cluster-ca = {
        enable = true;
        generateLeaf = false;
      };

      services.initrd-ssh-recovery = {
        enable = true;
        interface = "eth0";
        networkDriver = "r8169";
        port = 2222;
      };
      services.recovery-specialisation.enable = true;
      services.btrfs-boot-snapshot.enable = false;

      services.cachix-auth.enable = true;
      services.ai-coding-tools = {
        enable = true;
        user = "j_kro";
        context7ApiKeyFile = "/run/secrets/context7-api-key";
        nvidiaNimApiKeyFile = "/run/secrets/nvidia-api-key";
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
    }
  ];
}
