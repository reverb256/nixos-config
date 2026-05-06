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
    hermes-cli = {
    enable = true;
      apiKeyFile = config.age.secrets.zai-api-key.path;
  };
    k3s-cluster = {
    enable = true;
      nvidia.enable = true;
      role = "agent";
      nodeName = "forge";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = cluster.hosts.forge.ip;
  };

    spotify-spotx.enable = true;

    opencode.enable = true;

    nixos-share = {
    enable = true;
      client.enable = true;
  };

    mining.lolminer = {
      pool = "xtm-c29-us.kryptex.network:8040";
      wallet = "krxXVNVMM7.forge-gpu";
      pools = [
        {
          url = "xtm-c29-us.kryptex.network:8040";
          wallet = "krxXVNVMM7.forge-gpu";
          password = "x";
          tls = true;
        }
        {
          url = "xtm-c29-eu.kryptex.network:8040";
          wallet = "krxXVNVMM7.forge-gpu";
          password = "x";
          tls = true;
        }
      ];
  };

    gpu-proxy-cpp = {
    enable = true;
      listenPort = 3334;
      apiPort = 8083;
      logLevel = "INFO";
      pools = [
        {
          name = "Kryptex US";
          url = "xtm-c29-us.kryptex.network:8040";
          wallet = "krxXVNVMM7";
          password = "x";
          priority = 1;
          tls = true;
        }
        {
          name = "Kryptex EU";
          url = "xtm-c29-eu.kryptex.network:8040";
          wallet = "krxXVNVMM7";
          password = "x";
          priority = 2;
          tls = true;
        }
      ];
      workers = [
        {
          id = "krxXVNVMM7.forge-gpu";
          password = "x";
        }
        {
          id = "krxXVNVMM7.zephyr-gpu";
          password = "x";
        }
        {
          id = "krxXVNVMM7.nexus-gpu";
          password = "x";
        }
      ];
  };

    nfs-client = {
    enable = true;
      mountShared = true;
      mountHome = true;
      mountMedia = false;
  };

    syncthing-cluster = {
    enable = true;
      deviceId = "FORGE-PLACEHOLDER";
  };

    nixos-auto-update = {
    enable = true;
      interval = "daily";
      updateFlakeInputs = ["nixpkgs"];
  };

    agenix-secrets-registry = {
    enable = true;
      kubernetes = true;
      initrdRecovery = true;
      aiServices = true;
  };
  };

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
  services.initrd-ssh-recovery = {
    enable = true;
    interface = "eno1";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = true;
  services.btrfs-boot-snapshot = {
      enable = true;
      device = "/dev/disk/by-uuid/188a7c7c-fb81-4d48-96f6-3fd5f3a267df";
    };
}
