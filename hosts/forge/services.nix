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
      enable = false;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 90;
    };

    k3s-cluster = {
      enable = false;
      nvidia.enable = false;
      role = "server";
      clusterInit = false; # Rejoining existing cluster as server (for etcd quorum)
      nodeName = "forge";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = cluster.hosts.forge.ip;
    };

    spotify-spotx.enable = false;

    opencode.enable = false;

    # Agent network restrictions — restrict AI agents to allowed destinations only

    nixos-share = {
      enable = false;
      client.enable = false;
    };


    nfs-client = {
      enable = false;
      mountShared = true;
      mountHome = true;
      mountMedia = false;
    };

    srbminer = {
      enable = true;
      instances = [
        {
          name = "4060-0";
          gpuId = 0;
          wallet = "krxXVNVMM7.forge-4060-0";
          apiPort = 21550;
          powerLimit = 105;
        }
        {
          name = "4060-1";
          gpuId = 1;
          wallet = "krxXVNVMM7.forge-4060-1";
          apiPort = 21551;
          powerLimit = 105;
        }
      ];
    };


    syncthing-cluster = {
      enable = false;
    };

    hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      settings = {
        model = {
          provider = "opencode-go";
          default = "deepseek-v4-flash";
          base_url = "https://opencode.ai/zen/go/v1";
          api_mode = "chat_completions";
        };
        toolsets = ["all"];
        terminal = { backend = "local"; timeout = 60; };
        memory = { memory_enabled = true; user_profile_enabled = true; };
        compression = { enabled = true; threshold = 0.9; };
      };
    };

    nixos-auto-update = {
      enable = false;
      interval = "daily";
      updateFlakeInputs = ["nixpkgs"];
    };

  };

  users.users.j_kro.extraGroups = [
    "hermes"
  ];

  services.cluster-mesh.enable = false; # SSH service account for inter-node mesh
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
    enable = false;
    generateLeaf = false;
  };

  services.initrd-ssh-recovery = {
    enable = false;
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = false;
  services.btrfs-boot-snapshot = {
    enable = false;
    device = "/dev/disk/by-uuid/188a7c7c-fb81-4d48-96f6-3fd5f3a267df";
  };

  services.cachix-auth.enable = false;
  services.ai-coding-tools = {
    enable = false;
    user = "j_kro";
    zaiApiKeyFile = "/run/secrets/zai-api-key";
    context7ApiKeyFile = "/run/secrets/context7-api-key";
    nvidiaNimApiKeyFile = "/run/secrets/nvidia-api-key";
    opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
    tools = {
      claude = {enable = false;};
      opencode = {enable = false;};
      droid = {enable = false;};
      crush = {enable = false;};
      pi = {enable = false;};
      omp = {enable = false;};
    };
    enableShellEnv = true;
  };
}