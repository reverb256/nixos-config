{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  cluster = config.networking.cluster;
in {
  services = {
    keepalived-vip = {
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 90;
    };

    hermes-cli = {
      enable = true;
      apiKeyFile = config.age.secrets.zai-api-key.path;
      nvidiaApiKeyFile = config.age.secrets.nvidia-api-key.path;
      casdoorJwtFile = config.age.secrets.casdoor-hermes-jwt.path;
      opencodeGoApiKeyFile = config.age.secrets.opencode-go-api-key.path;
    };
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      clusterInit = false; # Rejoining existing cluster as server (for etcd quorum)
      nodeName = "forge";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = cluster.hosts.forge.ip;
    };

    syncthing-cluster = {
      enable = true;
    };
    spotify-spotx.enable = true;

    opencode.enable = true;
  };

  environment.systemPackages = with pkgs; [
    clinfo
    nvtopPackages.full
    inputs.claude-native.packages.x86_64-linux.claude
  ];

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
  services.btrfs-boot-snapshot = {
    enable = true;
    device = "/dev/disk/by-uuid/188a7c7c-fb81-4d48-96f6-3fd5f3a267df";
  };

  services.cachix-auth.enable = true;
  services.agenix-secrets-registry = {
    enable = true;
    aiServices = true;
    monitoring = false;
    storage = true;
    mining = true;
    cloud = true;
    kubernetes = true;
    automation = true;
    ci = true;
    initrdRecovery = true;
    selfHosting = true;
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
}
