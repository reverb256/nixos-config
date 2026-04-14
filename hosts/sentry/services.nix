# Sentry Service Configuration
# K3s control plane, monitoring stack (Loki), nginx, mining,
# NFS client, Syncthing, Gemma 4 E2B vision model (ROCm)
{ pkgs, lib, ... }:
{
  services = {
    # KUBERNETES - k3s control plane (joins existing cluster)
    k3s-cluster = {
      enable = true;
      role = "server";
      nodeName = "sentry";
      serverAddr = "https://10.1.1.100:6443";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = "10.1.1.140";
      calico.enable = true;
    };

    # Keepalived VIP for HA API server access
    keepalived-vip = {
      enable = true;
      vip = "10.1.1.100";
      interface = "enp7s0";
      priority = 90;
    };

    # Host Dashboard
    host-dashboard = {
      enable = true;
      role = "control-plane + monitoring";
      port = 8090;
      prometheusUrl = "http://127.0.0.1:9090";
      featuredServices = [
        {
          name = "Prometheus";
          url = "http://127.0.0.1:9090";
        }
        {
          name = "Grafana";
          url = "http://127.0.0.1:3000";
        }
        {
          name = "Loki";
          url = "http://127.0.0.1:3100";
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
          name = "cfssl";
          active = true;
        }
        {
          name = "keepalived";
          active = true;
        }
        {
          name = "xmrig";
          active = true;
        }
      ];
    };

    # Modular workload monitoring
    gaming-detection.enable = true;
    gpu-profile-manager.enable = true;
    mining-coordinator.enable = true;

    # Nginx - Lightweight static file server
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

    # MINING (CPU only - K8s deployment scaled to 0/0)
    mining = {
      xmrig = {
        enable = false;
        autostart = false;
        threads = 4;
        pool = "10.1.1.110:3333";
      };
      xmrigDual = {
        enable = true; # Enable for 1GB hugepages kernel params
        alwaysOn = {
          enable = false;
        };
      };
    };

    # Spotify with SpotX patch
    spotify-spotx.enable = true;

    # Tailscale
    tailscale.enable = true;

    # Mount /etc/nixos from zephyr
    nixos-share = {
      enable = true;
      client.enable = true;
    };

    # NFS Client - Mount shared storage from nexus
    nfs-client = {
      enable = true;
      mountShared = true;
      mountHome = false;
      mountMedia = false;
    };

    # Syncthing P2P file sync
    syncthing-cluster = {
      enable = true;
      deviceId = "SENTRY-PLACEHOLDER";
    };

    # Garage S3 disabled
    garage-cluster.enable = false;

    # Llamafile - LLM inference (TEMPORARILY DISABLED)
    # Gemma 4 E2B with vision on AMD RX 5600 XT (ROCm)
    llamafile = {
      enable = true;
      modelPath = /home/j_kro/.lmstudio/models/unsloth/gemma-4-E2B-it-GGUF/gemma-4-E2B-it-IQ4_NL.gguf;
      mmprojPath = /home/j_kro/.lmstudio/models/unsloth/gemma-4-E2B-it-GGUF/mmproj-F32.gguf;
      modelName = "gemma4-e2b";
      host = "0.0.0.0";
      port = 8888;
      gpu = "amd";
      gpuLayers = 99;
      ctxSize = 32768;
      threads = 4;
      flashAttention = true;
      cacheTypeK = "q4_0";
      cacheTypeV = "q4_0";
      temperature = 1.0;
      topK = 64;
      topP = 0.95;
    };

    # Unbound DNS
    unbound-common.enable = true;

    # Agenix secrets
    agenix-secrets-registry = {
      enable = true;
      mining = true;
      kubernetes = true;
    };
  };

  # Display driver
  services.xserver.videoDrivers = [ "amdgpu" ];

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

  # ============================================================================
  # TAILSCALE - Sentry advertises subnet routes (backup gateway)
  # ============================================================================
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };
}
