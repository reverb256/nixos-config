{
  config,
  lib,
  pkgs,
  inputs, ...
}: let
  cluster = config.networking.cluster;
in {
  services = {
    hermes-cli = {
      enable = true;
      apiKeyFile = "/run/secrets/zai-api-key";
      nvidiaApiKeyFile = "/run/secrets/nvidia-api-key";
      casdoorJwtFile = "/run/secrets/casdoor-hermes-jwt";
      opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
      opencodeZenApiKeyFile = "/run/secrets/opencode-api-key";
    };
    k3s-cluster = {
      enable = true;
      role = "server";
      nodeName = "sentry";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = cluster.hosts.sentry.ip;
    };

    keepalived-vip = {
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
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

    nixos-share = {
      enable = false;
      client.enable = true;
    };

    nfs-client = {
      enable = false;
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

    agenix-secrets-registry = {
      enable = true;
      kubernetes = true;
      initrdRecovery = true;
      aiServices = true;
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
    tokenFile = "/run/agenix/github-runner-pat";
    autoStart = true;
    extraLabels = ["sentry"];
  };


}