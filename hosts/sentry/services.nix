{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
in {
  services = {
    hermes-cli = {
      enable = true;
      apiKeyFile = config.age.secrets.zai-api-key.path;
      nvidiaApiKeyFile = config.age.secrets.nvidia-api-key.path;
      casdoorJwtFile = config.age.secrets.casdoor-hermes-jwt.path;
      opencodeGoApiKeyFile = config.age.secrets.opencode-go-api-key.path;
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

    spotify-spotx.enable = true;

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

    # Create directories for hermes/pi bind mounts on Sentry
    systemd.tmpfiles.rules = [
      "d /data/hermes 0775 j_kro j_kro -"
      "d /data/pi 0775 j_kro j_kro -"
    ];

    syncthing-cluster = {
      enable = true;
      deviceId = "SENTRY-PLACEHOLDER";
    };

    agenix-secrets-registry = {
      enable = true;
      kubernetes = true;
      initrdRecovery = true;
      aiServices = true;
    };
  };

  # Cluster DNS configuration
  networking.cluster.dns.enable = true;

  services.xserver.videoDrivers = ["amdgpu"];

  programs.nix-ld.libraries = with pkgs; [
    rocmPackages.clr
    rocmPackages.clr.icd
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
    rocmPackages.rocm-runtime
    rocmPackages.rocblas
    rocmPackages.hipblas
    rocmPackages.hipsparse
    rocmPackages.rocfft
    rocmPackages.rocrand
    rocmPackages.rocthrust
    ocl-icd
    opencl-headers
    clinfo
    zlib
    libpng
    libjpeg
    freetype
    fontconfig
    libx11
    libxext
    libxrender
    libxcb
    libxau
    libxdmcp
    SDL2
    alsa-lib
    systemd
    libusb1
    curl
    openssl
  ];

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
  services.btrfs-boot-snapshot = {
    enable = true;
    device = "/dev/disk/by-uuid/8ed4264a-6837-4af8-876a-1111625d98d1";
  };

  services.cachix-auth.enable = true;
   services.ai-coding-tools = {
     enable = true;
     user = "j_kro";
     zaiApiKeyFile = config.age.secrets.zai-api-key.path;
     context7ApiKeyFile = config.age.secrets.context7-api-key.path;
     nvidiaNimApiKeyFile = config.age.secrets.nvidia-api-key.path;
     opencodeGoApiKeyFile = config.age.secrets.opencode-go-api-key.path;
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

   # Agent network restrictions — restrict AI agents to allowed destinations only
   services.agent-firewall = {
     enable = true;
     auditLog = true;
   };
 }

