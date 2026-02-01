# Sentry Host Configuration
# 10.1.1.140 - Monitoring Server (8 cores, RX 5600 XT)
{pkgs, ...}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
    # Import desktop module for Plasma 6
    ../../modules/desktop.nix
    # Import AMD GPU Wayland module
    ../../modules/amdgpu-wayland.nix
    # Import OpenClaw AI agent orchestration
    ../../modules/openclaw.nix
    # Import OpenClaw common configuration
    ../../modules/openclaw-common.nix
  ];

  # Host identification
  networking.hostName = "sentry";

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

  # Sentry-specific overrides - CPU mining only
  services.mining.enable = true;
  services.mining.xmrig.enable = true;
  services.mining.xmrig.threads = 8;
  services.mining.xmrig.pool = "xtm-rx-us.kryptex.network:8038";
  services.mining.xmrig.wallet = "krxXVNVMM7.sentry";
  services.mining.lolminer.enable = false; # No GPU mining

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
  # OPENCLAW - AI Agent Gateway
  # ============================================================================
  services.openclaw = {
    enable = true;
    common = {
      enable = true; # Use common configuration for all nodes
    };
    # Let OpenClaw handle model configuration via its auth system
    settings = {};
  };

  # ============================================================================
  # FIREWALL (Base config - no extra ports)
  # ============================================================================

  networking.firewall = {
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };
}
