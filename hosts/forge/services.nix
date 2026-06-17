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
      apiKeyFile = "/run/secrets/zai-api-key";
      nvidiaApiKeyFile = "/run/secrets/nvidia-api-key";
      casdoorJwtFile = "/run/secrets/casdoor-hermes-jwt";
      opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
      opencodeZenApiKeyFile = "/run/secrets/opencode-api-key";
    };

    hermes-agent = {
      addToSystemPackages = true;
      settings = {
        providers.zai = {
          base_url = "https://api.z.ai/api/coding/paas/v4";
          api_key_env = "ZAI_API_KEY";
          discover_models = true;
        };
        providers.nvidia = {
          base_url = "https://integrate.api.nvidia.com/v1";
          api_key_env = "NVIDIA_API_KEY";
          discover_models = true;
        };
      };
    };

    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "server";
      clusterInit = false; # Rejoining existing cluster as server (for etcd quorum)
      nodeName = "forge";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = cluster.hosts.forge.ip;
    };

    spotify-spotx.enable = true;

    opencode.enable = true;

    # Agent network restrictions — restrict AI agents to allowed destinations only

    nixos-share = {
      enable = false;
      client.enable = true;
    };


    nfs-client = {
      enable = false;
      mountShared = true;
      mountHome = true;
      mountMedia = false;
    };

    lpminer = {
      enable = true;
      instances = [
        {
          name = "4060-0";
          gpuId = 0;
          wallet = "krxXVNVMM7.forge-4060-0";
          pool = "stratum+ssl://prl-us.kryptex.network:8048,stratum+ssl://prl.kryptex.network:8048";
          powerLimit = 105;
        }
        {
          name = "4060-1";
          gpuId = 1;
          wallet = "krxXVNVMM7.forge-4060-1";
          pool = "stratum+ssl://prl-us.kryptex.network:8048,stratum+ssl://prl.kryptex.network:8048";
          powerLimit = 105;
        }
      ];
    };


    syncthing-cluster = {
      enable = true;
    };

    nixos-auto-update = {
      enable = true;
      interval = "daily";
      updateFlakeInputs = ["nixpkgs"];
    };

    sops-secrets-registry = {
      enable = true;
      kubernetes = true;
      aiServices = true;
    };
  };

  services.cluster-mesh.enable = true; # SSH service account for inter-node mesh
  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
    clinfo
    nvtopPackages.full
    inputs.claude-native.packages.x86_64-linux.claude
  ];

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
    libGL
    libGLU
    libglvnd
    vulkan-loader
    nvidia-vaapi-driver
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
  services.btrfs-boot-snapshot.enable = lib.mkForce false; # removed snapshotting

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
}