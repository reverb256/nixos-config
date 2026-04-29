{ config, lib, pkgs, ... }:
let
  cluster = config.networking.cluster;
in
{
  services = {
    hermes-cli = {
      enable = true;
      apiKeyFile = config.age.secrets.zai-api-key.path;
    };
    k3s-cluster = {
      enable = true;
      role = "server";
      nodeName = "sentry";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/agenix/k3s-cluster-token";
      nodeIP = cluster.hosts.sentry.ip;
      calico.enable = false;
    };

    keepalived-vip = {
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "enp7s0";
      priority = 90;
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
      sourceHost = "zephyr";
    };

    syncthing-cluster = {
      enable = true;
      deviceId = "SENTRY-PLACEHOLDER";
    };

    garage-cluster.enable = false;


    agenix-secrets-registry = {
      enable = true;
      kubernetes = true;
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
}