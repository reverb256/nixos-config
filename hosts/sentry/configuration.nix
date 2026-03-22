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
  inputs,
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
    ../../modules/hardware/rgb-control.nix

    # Podman support
    ../../modules/services/podman-support.nix

    # Kubernetes HA modules
    ../../modules/services/kubernetes.nix
    ../../modules/services/keepalived-vip.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  clusterNetworking = {
    enable = true;
    hostName = "sentry";
    ipAddress = "10.1.1.140";
    interfaceName = "enp7s0"; # Native hardware interface name
    wireless.enable = false; # Monitoring node - no WiFi needed
    unbound.listenAddress = "10.1.1.140"; # Listen on node IP for cluster DNS
  };

  # Disable flake-lock-sync (nixos-shared mount not available)
  services.flake-lock-sync.enable = lib.mkForce false;

  # Directly disable the systemd timer (blocking rebuilds)
  systemd.timers.flake-lock-sync.enable = false;

  # STATUS.md auto-update (hourly from kubectl)
  services.status-auto-update.enable = true;

  # Populate /etc/hosts from central cluster configuration
  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };
    # Kubernetes worker firewall rules
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        22
        10250
        3100
        3900
        3901
      ]; # SSH + Kubelet API + Loki + Garage (merges with cluster defaults)
      allowedTCPPortRanges = lib.mkOptionDefault [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [8472]; # Flannel VXLAN (merges with cluster defaults)
      # Open Loki port on main interface for cluster access (module only opens on tailscale0)
      interfaces."enp7s0".allowedTCPPorts = [3100];
    };
  };

  # ============================================================================
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  profiles.node.sentry-monitoring.enable = true;

  # ============================================================================
  # GPU COMPUTE - ROCm/Vulkan support for AI inference
  # ============================================================================
  hardware.gpu-compute = {
    enable = true;
    # autoDetect removed - not needed
    # ROCm for AMD-specific compute (5600XT)
    rocm.enable = true;
    # Vulkan as universal backend
    vulkan.enable = true;
  };

  # ============================================================================
  # SERVICES - All service configurations
  # ============================================================================
  services = {
    # TEMPORARY: Worker-only node until HA expansion
    kubernetes-module = {
      enable = true;
      # Worker-only for now (will promote to master during HA expansion)
      roles = lib.mkForce ["node"];
      masterAddress = "10.1.1.110"; # Points to Zephyr
    };

    # TEMPORARY: Disable etcd and VIP until HA expansion
    # etcd-cluster = {
    #   enable = true;
    #   nodeName = "sentry";
    # };
    # keepalived-vip = {
    #   enable = true;
    #   vip = "10.1.1.100";
    #   interface = "enp7s0";
    #   priority = 90;
    # };

    # Host Dashboard - Web interface for cluster host status
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
  };

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  # Base profiles provided by node-profiles.sentry-monitoring:
  # - amd.zen, amdgpu.enable, amdgpu.wayland, monitoring.enable
  #
  # Sentry-specific hardware additions:
  hardware = {
    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring extras (not covered by profile)
    monitoring = {
      autoDetect = false; # Disabled: sensors-detect path issues
      fanControl = false; # BIOS fan control for now
    };

    # RGB control for AMD Wraith Prism cooler and MSI motherboard
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      wraithRgb.enable = true; # AMD Wraith Prism cooler
      temperatureReactive = {
        enable = true;
        sensor = "cpu"; # Monitor CPU temps
        thresholds = {
          cool = 45;
          warm = 60;
          hot = 70;
        };
        interval = 5;
      };
    };
  };

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  # Base role profiles provided by node-profiles.sentry-monitoring:
  # - mining, aiInference
  # Kubernetes and networking also handled by node profile
  #
  # No additional role profiles needed - all handled by node profile

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  # Base Tailscale configuration provided by node-profiles.sentry-monitoring
  # No additional network profile configuration needed

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================
  services = {
    # Crash detection and logging
    crash-watchdog.enable = true;

    # Compute Workload Monitor - Pause mining during builds/gaming
    compute-workload-monitor.enable = true;

    # Nginx - Serve Akash provider dashboards
    nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedGzipSettings = true;

      virtualHosts."_" = {
        default = true;
        locations."=/akash-health/" = {
          alias = "/var/www/akash-health/";
          extraConfig = ''
            autoindex off;
          '';
        };
        locations."=/akash-status/" = {
          alias = "/var/www/akash-status/";
          extraConfig = ''
            autoindex off;
          '';
        };
        # Root redirects to status page
        locations."= /".return = "301 /akash-status/";
      };
    };

    xserver.videoDrivers = ["amdgpu"];

    # MINING (CPU only - 4 threads = 25% of 16 cores)
    # Uses xmrig-proxy on Zephyr for centralized hashrate aggregation
    # Note: profiles.role.mining enables services.mining automatically
    # Sentry: CPU mining DISABLED - K8s deployment scaled to 0/0
    # RX 5600 XT reserved for AI inference (llamafile ROCm)
    mining = {
      xmrig = {
        enable = false;  # Disabled - K8s xmrig-sentry deployment scaled to 0/0
        autostart = false;
        threads = 4;
        pool = "10.1.1.110:3333"; # xmrig-proxy on Zephyr
        wallet = "sentry-cpu"; # Worker ID for proxy
        tls = false; # No TLS needed for local proxy
        httpTokenFile = "/run/agenix/xmrig-api-token"; # For HTTP API control
      };
      # AMD GPU (RX 5600 XT) - DISABLED for AI inference
      # Sentry should only CPU mine, GPU reserved for llamafile (ROCm)
      # lolminer = {
      #   enable = true;
      #   amd = {
      #     enable = true;
      #     autostart = true;
      #     devices = "0"; # RX 5600 XT (single AMD GPU)
      #     powerLimit = 140; # Safe power limit for RX 5600 XT
      #     apiPort = 4069;
      #   };
      #   # Use local xmrig-proxy on Zephyr for pooled mining
      #   pool = "10.1.1.110:3334";
      #   wallet = "krxXVNVMM7.sentry-gpu";
      #   pools = [
      #     {
      #       url = "10.1.1.110:3334"; # gpu-proxy on Zephyr
      #       wallet = "krxXVNVMM7.sentry-gpu";
      #       password = "x";
      #       tls = false;
      #     }
      #     {
      #       url = "xtm-c29-us.kryptex.network:8040"; # Direct Kryptex US (failover)
      #       wallet = "krxXVNVMM7.sentry-gpu";
      #       password = "x";
      #       tls = true;
      #     }
      #     {
      #       url = "xtm-c29-eu.kryptex.network:8040"; # Direct Kryptex EU (failover)
      #       wallet = "krxXVNVMM7.sentry-gpu";
      #       password = "x";
      #       tls = true;
      #     }
      #   ];
      # };
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

    # NFS Client - Mount shared storage from nexus
    nfs-client = {
      enable = true;
      mountShared = true;
      mountHome = false;
      mountMedia = false;
    };

    # Syncthing P2P file sync for /etc/nixos config sync
    syncthing-cluster = {
      enable = true;
      deviceId = "SENTRY-PLACEHOLDER";
    };

    # Garage S3 disabled - using nexus as primary storage node
    # Access Garage S3 at: http://10.1.120:3900
    # Note: /storage/garage directory still exists for local use
    garage-cluster.enable = false;

    # Hermes Agent is now configured at top-level as services.hermes-agent
  };

  # ============================================================================
  # HERMES AGENT - Multi-Host Orchestration
  # ============================================================================
  # Autonomous agent for cluster-wide task execution and coordination
  # DISABLED: Health check blocking rebuilds (2026-03-21)
  services.hermes-agent = {
    enable = false;
    user = "j_kro";
    sharedStorage = {
      enable = true;
      mountPoint = "/home/j_kro/.hermes";
      nfsServer = "10.1.1.120"; # Nexus NFS server
      nfsPath = "/mnt/garage/hermes";
    };
    aiGateway = {
      enable = true;
      url = "http://10.1.1.110:8080/v1"; # Zephyr AI Gateway
    };
    terminal = {
      enable = true;
      requireApproval = false;
    };
  };

  # ============================================================================
  # BOOTLOADER CONFIGURATION
  # ============================================================================
  # Moved from hardware-configuration.nix for centralized config
  # Base bootloader settings provided by common-host-defaults.nix:
  # - systemd-boot.enable, efi.canTouchEfiVariables, kernelPackages (linux_zen)
  boot.loader.timeout = lib.mkDefault 5;

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
      rocmPackages.rocminfo
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
  # Defined in hardware-configuration.nix with subvol=@data
  # ============================================================================

  # Host-specific Tailscale override: Sentry advertises subnet routes (backup gateway)
  # This overrides the base Tailscale configuration from node profile
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

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

    # Git configuration now provided by common-host-defaults.nix
    # Sentry-specific git remote override (if needed):
    # programs.git.config.remote.origin.url = "git@github.com:reverb256/nixos-config.git";
  };

  # ============================================================================
  # AGENIX SECRETS
  # ============================================================================
  # Centralized registry - see modules/system/agenix-secrets-registry.nix
  services.agenix-secrets-registry = {
    enable = true;
    mining = true; # XMRig API token
  };

  # Override specific secret permissions for mining service
  age.secrets.xmrig-api-token = lib.mkForce {
    file = "${inputs.self}/secrets/xmrig-api-token.age";
    mode = "440";
    owner = "mining";
    group = "mining";
  };
  # ============================================================================
  # LLAMAFILE - LLM INFERENCE SERVICE (AMD RX 5600 XT - Vulkan)
  # ============================================================================
  # TEMPORARILY DISABLED: llama-cpp-rocm build failing
  # Re-enable after nixpkgs update or switch to CPU/Vulkan backend
  services.llamafile = {
    enable = false;
    # modelPath = "/home/j_kro/.lmstudio/models/unsloth/Qwen3.5-2B-GGUF/Qwen3.5-2B-IQ4_NL.gguf";
    # host = "0.0.0.0";
    # port = 8086;
    # gpu = "rocm";
    # gpuLayers = 999;
    # ctxSize = 16384;
    # threads = 8;
    # batchSize = 512;
    # ubatchSize = 512;
    # flashAttention = false;
    # enableThinking = false;
    # reasoningBudget = 0;
    # cacheTypeK = "bf16";
    # cacheTypeV = "bf16";
  };
}
