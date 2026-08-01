{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cluster = config.networking.cluster;
in {
  services = {
    k3s-cluster = {
      enable = false;
      role = "server";
      etcdClean = true;
      nodeName = "sentry";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = cluster.hosts.sentry.ip;
      secretsEncryptionKeyFile = "/run/secrets/k3s-encryption-key";
    };

    keepalived-vip = {
      enable = false;
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




    sops-secrets-registry = {
      enable = false;
      kubernetes = true;
      aiServices = true;
      ci = true;
    };
    sops-secrets-registry = {
      enable = false;
      kubernetes = true;
      aiServices = true;
      ci = true;
    };

  services.cluster-mesh.enable = true; # SSH service account for inter-node mesh
  systemd.tmpfiles.rules = [
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
    generateLeaf = false;
  };

  services.initrd-ssh-recovery = {
    enable = true;
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = true;
  services.btrfs-boot-snapshot.enable = lib.mkOptionDefault false;  # NixOS generations sufficient; hosts can override with plain = true

  services.cachix-auth.enable = true;
  services.ai-coding-tools = {
    enable = true;
    user = "j_kro";
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
}
