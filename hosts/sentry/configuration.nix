# Sentry Host Configuration - Monitoring Server
# 10.1.1.140 - 16 cores, RX 5600 XT
# Features: Gaming only (no VR), CPU mining, ROCm
#
# Module imports: Gaming, mining, monitoring, opencode are already imported
# via commonModules in flake.nix (./modules/default.nix)
# Gaming module is used here for Plasma desktop gaming optimizations
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # All other modules (desktop, gaming, networking, services, etc.)
    ../../modules/default.nix

    # AMD GPU Wayland optimizations (includes nvtopPackages.full)
    ../../modules/hardware/amdgpu-wayland.nix

    # Plasma6 desktop (includes autologin configuration)
    ../../modules/desktop/plasma6.nix

    # Podman support
    ../../modules/services/podman-support.nix

    # Home Manager integration
    ../../modules/system/home-manager.nix

    # Kubernetes worker node
    ../../modules/services/kubernetes.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  clusterNetworking = {
    enable = true;
    hostName = "sentry";
    ipAddress = "10.1.1.140";
    interfaceName = "enp7s0";  # Native hardware interface name
    wireless.enable = false;  # Monitoring node - no WiFi needed
    unbound.listenAddress = "10.1.1.140";  # Listen on node IP for cluster DNS
  };

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  hardware = {
    profiles = {
      amd.zen = true; # Zen CPU optimizations
      amdgpu.enable = true; # AMD GPU support
      amdgpu.wayland = true; # AMDGPU Wayland optimizations (ROC_ENABLE_PRE_VEGA)
      monitoring.enable = true; # Hardware monitoring
    };

    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = false; # Disabled: sensors-detect path issues
      fanControl = false; # BIOS fan control for now
    };
  };

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  profiles.role = {
    mining = true; # CPU mining only
    aiInference = true; # AI inference gateway + MCP + RAG
  };

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  profiles.network.tailscale.enable = true;

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================
  services = {
    # Kubernetes worker node
    kubernetes-module = {
      enable = true;
      masterAddress = "10.1.1.110"; # Zephyr control plane
      roles = ["node"]; # Worker node only
    };

    xserver.videoDrivers = ["amdgpu"];

    # MINING (CPU only - 8 threads = 50% of 16 cores)
    # Uses xmrig-proxy on Zephyr for centralized hashrate aggregation
    # Note: profiles.role.mining enables services.mining automatically
    # Sentry: RX 5600 XT available but not used for mining
    mining = {
      xmrig = {
        enable = true;
        autostart = true;
        threads = 8;
        pool = "10.1.1.110:3333";  # xmrig-proxy on Zephyr
        wallet = "sentry-cpu";      # Worker ID for proxy
        tls = false;                 # No TLS needed for local proxy
      };
      lolminer.enable = false; # No GPU mining on Sentry
    };

    # Spotify with SpotX patch (ad-free, premium features)
    spotify-spotx.enable = true;

    # TAILSCALE
    tailscale.enable = true;

    # Mount /etc/nixos from zephyr (single-source-of-truth)
    nixos-share = {
      enable = true;
      client.enable = true;
    };
  };

  # ============================================================================
  # BOOTLOADER CONFIGURATION
  # ============================================================================
  # Moved from hardware-configuration.nix for centralized config
  boot.loader = {
    systemd-boot = {
      enable = true;
    };
    efi = {
      canTouchEfiVariables = true;
    };
    timeout = lib.mkDefault 5;
  };

  # Environment configuration
  environment = {
    # ROCm SETUP (for AMD GPU monitoring)
    # Note: hardware.profiles.amdgpu.wayland sets ROC_ENABLE_PRE_VEGA=1 automatically
    variables = {
      LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
      OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
    };

    systemPackages = with pkgs; [
      rocmPackages.rocm-smi
    ];
  };

  systemd.tmpfiles.rules = let
    rocmEnv = pkgs.symlinkJoin {
      name = "rocm-combined";
      paths = with pkgs.rocmPackages; [
        clr
        clr.icd
        rocblas
        hipblas
        rpp
      ];
    };
  in [
    "L+ /opt/rocm - - - - ${rocmEnv}"
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];

  # ============================================================================
  # SECONDARY STORAGE (sda - 1TB SSD)
  # ============================================================================
  fileSystems."/storage" = {
    device = "/dev/disk/by-uuid/4cc9468d-166d-4479-9846-6224c80d9566";
    fsType = "btrfs";
    options = ["subvol=@data"];
  };

  # Kubernetes worker firewall rules
  networking.firewall = {
    allowedTCPPorts = lib.mkOptionDefault [22 10250]; # SSH + Kubelet API (merges with cluster defaults)
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 32767;
      }
    ];
    allowedUDPPorts = lib.mkOptionDefault [8472]; # Flannel VXLAN (merges with cluster defaults)
  };

  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # ============================================================================
  # NIX-LD (For ROCm and mining software compatibility)
  # ============================================================================
  programs = {
    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [
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
      xorg.libX11
      xorg.libXext
      xorg.libXrender
      xorg.libxcb
      xorg.libXau
      xorg.libXdmcp
      SDL2
      alsa-lib
      systemd
      libusb1
      curl
      openssl
    ];

    git = {
      enable = true;
      config = {
        user.name = "j_kro";
        user.email = "j_kro@sentry";
        init.defaultBranch = "main";
        remote.origin.url = "git@github.com:reverb256/nixos-config.git";
      };
    };
  };
}
