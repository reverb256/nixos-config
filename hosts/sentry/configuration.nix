# Sentry Host Configuration
# 10.1.1.140 - Monitoring Server (8 cores, RX 5600 XT)
{...}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
    # Import desktop module for Plasma 6
    ../../modules/desktop.nix
    # Import AMD GPU Wayland module
    ../../modules/amdgpu-wayland.nix
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
  # FIREWALL (Base config - no extra ports)
  # ============================================================================

  networking.firewall = {
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };
}
