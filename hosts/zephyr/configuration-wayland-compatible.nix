# Zephyr Host Configuration - Wayland Compatible Version
# 10.1.1.110 - Master Workstation (32 cores, RTX 3090) - Wayland Desktop Focus
{...}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
    # Gaming features (removed for pure desktop experience)
    # ../../modules/gaming.nix
  ];

  # Host identification
  networking.hostName = "zephyr";

  # ============================================================================
  # BOOTLOADER - systemd-boot
  # ============================================================================

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # ============================================================================
  # WAYLAND-COMPATIBLE KERNEL PARAMETERS (Less aggressive for display stability)
  # ============================================================================

  boot.kernelParams = [
    # Basic NVIDIA optimizations
    "nvidia-drm.modeset=1"
    "threadirqs"

    # Ryzen 5950X optimizations (less aggressive)
    "amd_pstate=active"
    "mitigations=off"
    "transparent_hugepage=madvise"
    "numa_balancing=disable"
    "nowatchdog"

    # Standard I/O optimizations (less aggressive than gaming config)
    "elevator=none"
    # Removed: pcie_aspm=off, isolcpus, nohz_full, rcu_nocbs which interfere with compositor
  ];

  # ============================================================================
  # MINING CONFIGURATION (Zephyr: 32 cores, RTX 3090)
  # ============================================================================
  # Commenting out mining for a cleaner desktop experience
  # services.mining.enable = true;
  # services.mining.xmrig.enable = true;
  # services.mining.xmrig.threads = 30;
  # services.mining.xmrig.pool = "rx.unmineable.com:3333";
  # services.mining.xmrig.wallet = "krxXVNVMM7.zephyr";
  #
  # # Configure lolminer for NVIDIA RTX 3090
  # services.mining.lolminer.enable = true;
  # services.mining.lolminer.nvidia.enable = true;
  # services.mining.lolminer.nvidia.devices = "0";
  # services.mining.lolminer.algorithm = "CR29";
  # services.mining.lolminer.pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
  # services.mining.lolminer.wallet = "krxXVNVMM7.zephyr";

  # ============================================================================
  # NETWORKING (Static IP)
  # ============================================================================

  # Configure NetworkManager for ethernet with static IP
  networking.networkmanager.ensureProfiles = {
    profiles."Wired connection 1" = {
      connection = {
        id = "Wired connection 1";
        type = "ethernet";
        interface-name = "enp38s0";
        autoconnect = true;
      };
      ipv4 = {
        method = "manual";
        address1 = "10.1.1.110/24";
        gateway = "10.1.1.1";
        dns = "127.0.0.1,::1";
      };
      ipv6 = {
        method = "auto";
      };
    };
  };

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
  # FIREWALL (Reduced for desktop focus)
  # ============================================================================

  networking.firewall = {
    allowedTCPPorts = []; # Only essential ports
    allowedUDPPorts = [];
  };
}
