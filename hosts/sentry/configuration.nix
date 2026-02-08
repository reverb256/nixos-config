# Sentry Host Configuration
# 10.1.1.140 - Monitoring Server (8 cores, RX 5600 XT)
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
    # Import AMD GPU Wayland module
    ../../modules/amdgpu-wayland.nix
    # Import OpenClaw AI agent orchestration (declarative container)
    # Import OpenClaw common configuration
    # Import Tailscale mesh VPN
    ../../modules/tailscale.nix
    # Import CI/CD and auto-update modules
    ../../modules/garnix.nix
    ../../modules/auto-update.nix
    ../../modules/ssh.nix
    # Import distributed builds module (GPU+ROCm support)
    ../../modules/distributed-builds.nix
      # Import Kubernetes module - DISABLED (module conflict with nixpkgs)
      # ../../modules/services/kubernetes.nix
      # Import n8n module (custom with dbType option) - DISABLED (module conflict)
      # ../../modules/services/n8n.nix
      # Import stable-diffusion module - DISABLED (causing infinite recursion)
      # ../../modules/services/stable-diffusion.nix
      # Import OpenClaw node host module - DISABLED (OpenClaw refactor in progress)
      # ../../modules/openclaw-node-host.nix
    ];

  # Host identification
  networking.hostName = "sentry";

  # Enable CI/CD features
  services.garnix.enable = false;
  services.nixos-auto-update.enable = true;

  # Multi-kernel support: Use latest stable kernel temporarily (linux-zen 6.18.7 has module shrinkage bug)
  # boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # ============================================================================
  # DESKTOP ENVIRONMENT - KDE Plasma 6 with AMD GPU
  # ============================================================================

  services.xserver.enable = true;

  # AMD GPU Wayland configuration
  hardware.amdgpu.wayland = {
    enable = true;
    enable32Bit = true;
    opencl = false; # No GPU mining on Sentry
    sddmWayland = true;
  };

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

  # Sentry-specific overrides - CPU mining only (8 threads = 50% of 16 cores)
   services.mining.enable = true;
   services.mining.xmrig.enable = true;
   services.mining.xmrig.threads = 8;
   services.mining.xmrig.pool = "xtm-rx-us.kryptex.network:8038";
   services.mining.lolminer.enable = false; # No GPU mining on sentry

  # ============================================================================
  # NETWORKING (Static IP)
  # ============================================================================

  networking.interfaces.enp7s0.ipv4.addresses = [
    {
      address = "10.1.1.140";
      prefixLength = 24;
    }
  ];
  networking.defaultGateway = "10.1.1.1";

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
    package = pkgs.ollama-cpu; # CPU-only (AMD RX 5600 XT not used for LLM)
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "24h";
    };
  };

  # ============================================================================
  # FIREWALL (Base config - no extra ports)
  # ============================================================================

  networking.firewall = {
    allowedTCPPorts = [];
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

  programs.git = {
    enable = true;
    config = {
      user.name = "j_kro";
      user.email = "j_kro@sentry";
      init.defaultBranch = "main";
      remote.origin.url = "git@github.com:reverb256/nixos-config.git";
    };
  };

  # OpenClaw node host service - DISABLED (OpenClaw refactor in progress)
  # services.openclaw-node-host = {
  #   enable = true;
  #   gatewayHost = "zephyr";
  #   displayName = "Sentry Build Node";
  #   execAllowlist = [
  #     "/run/current-system/sw/bin/uname"
  #     "/run/current-system/sw/bin/sw_vers"
  #   ];
  # };

  # Additional services for AI and automation
  # n8n workflow automation - DISABLED (module conflict with nixpkgs)
  # services.n8n = {
  #   enable = true;
  #   port = 5678;
  #   host = "0.0.0.0";
  #   dbType = "sqlite";
  #   openFirewall = true;
  # };

  # Stable Diffusion - DISABLED (causing infinite recursion)
  # services.stable-diffusion = {
  #   enable = true;
  #   port = 7860;
  #   host = "0.0.0.0";
  #   gpuType = "cpu";  # Use CPU since no specific GPU mentioned
  #   cmdOptions = [
  #     "--opt-split-attention"
  #   ];
  #   openFirewall = true;
  # };

}
