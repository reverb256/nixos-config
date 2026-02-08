# Nexus Host Configuration
# 10.1.1.120 - Build Server (24 cores, 2x RTX 3060 Ti)
{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
    # Import desktop module for Plasma 6
    ../../modules/desktop.nix
    # Import fish shell with starship
    ../../modules/fish-starship.nix
    # Import gaming module
    ../../modules/gaming.nix
    # Import NVIDIA Wayland module (best practices)
    ../../modules/nvidia-wayland.nix
    # Import OpenClaw AI agent orchestration (declarative container)
    # Import OpenClaw common configuration
    # Import Tailscale mesh VPN
    ../../modules/tailscale.nix
    # Import AIStor secrets generation
    ../../modules/aistor-secrets.nix
    # Import mining module (robust configuration)
    ../../modules/mining.nix
    # Import CI/CD and auto-update modules
    ../../modules/garnix.nix
    ../../modules/auto-update.nix
    ../../modules/ssh.nix
    # Import OpenClaw node host module - DISABLED (OpenClaw refactor in progress)
    # Import distributed builds module (GPU+CUDA+ROCm support)
    ../../modules/distributed-builds.nix
    # Import OpenClaw node host module - DISABLED (OpenClaw refactor in progress)
  ];

  # Host identification
  networking.hostName = "nexus";

  # Enable CI/CD features
  services.garnix.enable = false;
  services.nixos-auto-update.enable = true;

  # Multi-kernel support: Zen primary kernel
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # ============================================================================
  # NVIDIA WAYLAND CONFIGURATION (RTX 3060 Ti)
  # ============================================================================
  hardware.nvidia = {
    package = pkgs.linuxPackages_zen.nvidiaPackages.stable;
  };

  # Enable NVIDIA Wayland optimizations
  hardware.nvidia.wayland = {
    enable = true;
    enable32Bit = true;
    openModules = true; # Use open-source kernel modules with proprietary userspace
    powerManagement = true;
    sddmWayland = true;
  };

  # Legacy X11 video driver setting (kept for compatibility)
  services.xserver.videoDrivers = ["nvidia"];

  services.displayManager = {
    sddm.enable = true;
    defaultSession = "plasma";
    autoLogin = {
      enable = true;
      user = "j_kro";
    };
  };

  # ============================================================================
  # PREVENT PLASMA SESSION KILL DURING REBUILD
  # ============================================================================
  # Stop display-manager from restarting during nixos-rebuild switch
  # This prevents Plasma 6 Wayland session termination on configuration changes
  systemd.services.display-manager.restartIfChanged = false;
  systemd.services.sddm.restartIfChanged = false;

  # Prevent systemd-logind from killing user processes during session changes
  services.logind.settings.Login.KillUserProcesses = false;

  # Disable OpenRGB on nexus (no RGB devices)
  hardware.rgb.openrgb.enable = lib.mkForce false;

  # ============================================================================
  # MINING CONFIGURATION (Nexus: 24 cores, RTX 3060 Ti)
  # ============================================================================
  services.mining = {
    enable = true;
    user = "mining";
    xmrig = {
      enable = true;
      threads = 16;
      pool = "xtm-rx-us.kryptex.network:8038";
      wallet = "krxXVNVMM7.nexus";
    };
    lolminer = {
      enable = true;
      algorithm = "CR29";
      pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
      nvidia = {
        enable = true;
        devices = "0"; # Use only first RTX 3060 Ti
        powerLimit = 130; # 130W power limit
      };
    };
  };

  # ============================================================================
  # NETWORKING (Static IP via NetworkManager - required for desktop environment)
  # ============================================================================

  # Configure NetworkManager for static IP (desktop environment requires NetworkManager)
  networking.networkmanager = {
    enable = true;
    unmanaged = []; # Let NetworkManager manage all interfaces
    ensureProfiles.profiles."enp7s0" = {
      connection = {
        id = "enp7s0";
        type = "ethernet";
        interface-name = "enp7s0";
      };
      ipv4 = {
        method = "manual";
        address1 = "10.1.1.120/24";
        gateway = "10.1.1.1";
        dns = "127.0.0.1,::1"; # Use local Unbound DNS
      };
    };
  };

  networking.dhcpcd.enable = false;
  networking.useDHCP = false;

  # ============================================================================
  # LOCAL HOSTS ENTRIES
  # ============================================================================

  networking.hosts = {
    "10.1.1.110" = ["zephyr"];
    "10.1.1.120" = ["nexus"];
    "10.1.1.130" = ["forge"];
    "10.1.1.140" = ["sentry"];
  };

  # ============================================================================
  # OLLAMA - Local LLMs
  # ============================================================================
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda; # Use NVIDIA RTX 3060 Ti
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "24h";
    };
  };

  # ============================================================================
  # AISTOR / MINIO S3 CACHE SERVER + AI DATA STORE
  # ============================================================================
  # Note: MinIO will use generated credentials from systemd service
  # Credentials will be generated at /tmp/aistor-credentials.env by:
  # systemd service aistor-generate-credentials (runs at boot)
  #
  # For manual credential setup, see AISTOR-DEPLOY.md

  services.minio = {
    enable = true;
    listenAddress = "10.1.1.120:9000";
    consoleAddress = "10.1.1.120:9001";
    region = "us-east-1";
    # Data directory (use your large storage)
    dataDir = ["/var/lib/minio"];
    # Root credentials (will be generated by aistor-secrets service on first boot)
    # For now, MinIO will use default credentials (minioadmin/minioadmin)
    # environmentFile = "/tmp/aistor-credentials.env";
  };

  # MCP Server environment (when AIStor MCP goes GA)
  # Currently in tech preview - requires enterprise license for full features
  # For now, use S3 API as bridge via aistor-ops.py script
  environment.variables = {
    # AIStor MCP endpoint (future use)
    AISTOR_MCP_ENDPOINT = "http://10.1.1.120:9000";
    # S3 API endpoint (current)
    AISTOR_S3_ENDPOINT = "http://10.1.1.120:9000";
    # Default buckets for AI ops
    AISTOR_BUCKET_MODELS = "ai-models";
    AISTOR_BUCKET_DATA = "training-data";
    AISTOR_BUCKET_EXPERIMENTS = "experiments";
    AISTOR_BUCKET_CACHE = "nix-cache";
  };

  # Create data directory for MinIO/AIStor
  systemd.tmpfiles.settings.minio = {
    "/var/lib/minio" = {
      d = {
        user = "minio";
        group = "minio";
        mode = "0755";
      };
    };
  };

  # Open firewall for MinIO
  networking.firewall = {
    allowedTCPPorts = [
      9000 # MinIO S3 API
      9001 # MinIO Console
    ];
    allowedUDPPorts = [];
  };

  # ============================================================================
  # TAILSCALE - Secure mesh VPN (using standard nixpkgs module)
  # ============================================================================
  services.tailscale = {
    enable = true;
  };

  # Routing features configured via tailscaled environment
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # OpenClaw node host service - DISABLED (OpenClaw refactor in progress)
  #   enable = true;
  #   gatewayHost = "zephyr";
  #   displayName = "Nexus Build Node";
  #   execAllowlist = [
  #     "/run/current-system/sw/bin/uname"
  #     "/run/current-system/sw/bin/sw_vers"
  #   ];
  # };
}
