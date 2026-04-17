{ pkgs, lib, ... }:
{
  services = {
    hermes-cli = {
      enable = true;
      apiKey = "a304de1a9f0e46fb870d59d884b9616c.4Zeci63KC3W6FzuR";
    };
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "agent";
      nodeName = "forge";
      serverAddr = "https://10.1.1.100:6443";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = "10.1.1.130";
    };

    spotify-spotx.enable = true;

    opencode.enable = true;

    nixos-share = {
      enable = true;
      client.enable = true;
    };

    mining.lolminer = {
      nvidia = {
        enable = false;
        autostart = false;
        devices = "2,3";
        powerLimit = 90;
        memoryClockLock = 8501;
        apiPort = 4068;
      };
      amd = {
        enable = false;
        autostart = false;
        devices = "0,1";
        powerLimit = 110;
        apiPort = 4069;
      };
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
      mountMedia = true;
    };

    syncthing-cluster = {
      enable = true;
      deviceId = "FORGE-PLACEHOLDER";
    };

    nixos-auto-update = {
      enable = true;
      interval = "daily";
      updateFlakeInputs = [ "nixpkgs" ];
    };

    unbound-common.enable = true;

    agenix-secrets-registry = {
      enable = true;
      kubernetes = true;
    };
  };

  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
    clinfo
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
}
