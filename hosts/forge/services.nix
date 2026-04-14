# Forge Service Configuration
# Kubernetes worker, GPU mining proxy, NFS client, mining config
{ pkgs, lib, ... }:
{
  services = {
    # KUBERNETES - k3s agent (worker only)
    k3s-cluster = {
      enable = true;
      nvidia.enable = true;
      role = "agent";
      nodeName = "forge";
      serverAddr = "https://10.1.1.100:6443";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = "10.1.1.130";
    };

    # Spotify with SpotX patch
    spotify-spotx.enable = true;

    # OpenCode - AI coding assistant
    opencode.enable = true;

    # Mount /etc/nixos from zephyr (single-source-of-truth)
    nixos-share = {
      enable = true;
      client.enable = true;
    };

    # Mining configuration - lolminer for NVIDIA and AMD GPUs
    mining.lolminer = {
      # NVIDIA GPUs (2x RTX 4060) - MIGRATED TO KUBERNETES
      nvidia = {
        enable = false;
        autostart = false;
        devices = "2,3";
        powerLimit = 90;
        memoryClockLock = 8501;
        apiPort = 4068;
      };
      # AMD GPUs (RX 5700 XT) - NOW MANAGED BY K3S
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

    # C++ GPU Stratum Proxy for CR29
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

    # NFS Client - Mount shared storage from nexus
    nfs-client = {
      enable = true;
      mountShared = true;
      mountHome = true;
      mountMedia = true;
    };

    # Syncthing P2P file sync
    syncthing-cluster = {
      enable = true;
      deviceId = "FORGE-PLACEHOLDER";
    };

    # Host Dashboard
    host-dashboard = {
      enable = true;
      role = "compute + mining";
      port = 8090;
      prometheusUrl = "http://127.0.0.1:9090";
      featuredServices = [
        {
          name = "GPU Proxy";
          url = "http://127.0.0.1:8083";
        }
      ];
      services = [
        {
          name = "kubelet";
          active = true;
        }
        {
          name = "containerd";
          active = true;
        }
        {
          name = "gpu-proxy-cpp";
          active = true;
        }
        {
          name = "lolminer";
          active = true;
        }
      ];
    };

    # NIXOS AUTO-UPDATE
    nixos-auto-update = {
      enable = true;
      interval = "daily";
      updateFlakeInputs = [ "nixpkgs" ];
      extraFlags = [ "--upgrade" ];
    };

    # Unbound DNS
    unbound-common.enable = true;

    # Agenix secrets
    agenix-secrets-registry = {
      enable = true;
      kubernetes = true;
    };
  };

  # ============================================================================
  # PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
    clinfo # For debugging OpenCL
    # opencode now via home-manager
  ];

  # ============================================================================
  # NIX-LD - For mining software compatibility
  # ============================================================================
  programs.nix-ld.libraries = with pkgs; [
    # AMD/ROCm libraries
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
    # OpenCL
    ocl-icd
    opencl-headers
    clinfo
    # NVIDIA libraries
    libGL
    libGLU
    libglvnd
    vulkan-loader
    nvidia-vaapi-driver
    # System libraries
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
