# Nexus Host Configuration
# 10.1.1.120 - Build Server (24 cores, 2x RTX 3060 Ti)
{ ...}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
  ];

  # Host identification
  networking.hostName = "nexus";

  # ============================================================================
  # BOOTLOADER - systemd-boot
  # ============================================================================

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # ============================================================================
  # DESKTOP ENVIRONMENT - KDE Plasma 6
  # ============================================================================

  services = {
    xserver.enable = true;
    xserver.videoDrivers = ["nvidia"];
    displayManager = {
      sddm.enable = true;
      autoLogin = {
        enable = true;
        user = "j_kro";
      };
    };
    desktopManager.plasma6.enable = true;
  };

  # ============================================================================
  # MINING CONFIGURATION (Nexus: 24 cores, 2x RTX 3060 Ti)
  # ============================================================================
  services.mining.enable = true;
  services.mining.xmrig.enable = true;
  services.mining.xmrig.threads = 12;
  services.mining.lolminer.enable = true;
  services.mining.lolminer.nvidia.enable = true;
  services.mining.lolminer.nvidia.devices = "0,1";
  services.mining.lolminer.algorithm = "CR29";
  services.mining.lolminer.pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
  services.mining.lolminer.wallet = "krxXVNVMM7.nexus";

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
  # FIREWALL (Base config - no extra ports)
  # ============================================================================

  networking.firewall = {
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };
}
