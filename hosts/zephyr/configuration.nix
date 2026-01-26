# Zephyr Host Configuration
# 10.1.1.110 - Master Workstation (32 cores, RTX 3090)
{...}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
    # Gaming features
    ../../modules/gaming.nix
    # OpenAgents Control
    ../../modules/openagents-control.nix
  ];

  # Host identification
  networking.hostName = "zephyr";

   # ============================================================================
   # HOME MANAGER CONFIGURATION
   # ============================================================================
   
   home-manager = {
     useGlobalPkgs = true;
     useUserPackages = true;
     users.j_kro = { pkgs, ... }: {
       imports = [
         ../../modules/fish-starship.nix
       ];
       
       home = {
         username = "j_kro";
         homeDirectory = "/home/j_kro";
         stateVersion = "26.05";
       };
       
         programs = {
           home-manager.enable = true;
           fish = {
             enable = true;
           };
         };
       
       xdg = {
         enable = true;
         userDirs.enable = true;
       };
     };
   };
   
   # ============================================================================
   # BOOTLOADER - systemd-boot
   # ============================================================================

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # ============================================================================
  # HIGH-PERFORMANCE KERNEL PARAMETERS (made Wayland-compatible)
  # ============================================================================

  boot.kernelParams = [
    # Wine gaming performance
    "fsync.enable=1"

    # NVIDIA optimizations (desktop.nix adds nvidia-drm.modeset=1)
    "nvidia-drm.modeset=1"
    "threadirqs"
    
    # NEW: Enhanced NVIDIA RTX 3090 optimizations
    "nvidia.NVreg_RegistryDwords=PerfLevelSrc=0x2222"
    "nvidia.NVreg_UsePageAttributeTable=1" # Better memory management
    "nvidia.NVreg_EnableResizableBar=1" # Resizable BAR for RTX 3090

    # Ryzen 5950X optimizations (made compatible with Wayland)
    "amd_pstate=active"
    "mitigations=off"
    "transparent_hugepage=madvise"
    "numa_balancing=disable"
    "nowatchdog"

    # PCIe and I/O optimizations (removed aggressive options that interfere with wayland)
    "elevator=none"

    # High-priority gaming optimizations (disabled for Wayland compatibility)
    # "isolcpus=managed_applications" # CPU isolation - INTERFERES WITH WAYLAND COMPOSITOR
    # "nohz_full=1-15" # Disable tick on application cores - INTERFERES WITH WAYLAND COMPOSITOR
    # "rcu_nocbs=1-15" # RCU offload - INTERFERES WITH WAYLAND COMPOSITOR
  ];

  # ============================================================================
  # MINING CONFIGURATION (Zephyr: 32 cores, RTX 3090)
  # ============================================================================
  services.mining.enable = true;
  services.mining.xmrig.enable = true;
  services.mining.xmrig.threads = 16;
  services.mining.xmrig.pool = "xtm-rx-us.kryptex.network:8038";
  services.mining.xmrig.wallet = "krxXVNVMM7.zephyr";
  services.mining.lolminer.enable = true;
  services.mining.lolminer.nvidia.enable = true;
  services.mining.lolminer.nvidia.devices = "0";
  services.mining.lolminer.algorithm = "CR29";
  services.mining.lolminer.pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
  services.mining.lolminer.wallet = "krxXVNVMM7.zephyr";

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

  # OpenAgents Control Configuration
  services.openagents-control = {
    enable = true;
    installProfile = "advanced";  # Choose: essential, developer, business, full, or advanced
    installDir = "/home/j_kro/.config/opencode";
    autoUpdate = false;  # Temporarily disabled to fix service startup issue
  };

  # ============================================================================
  # FIREWALL (VR ports for WiVRn streaming)
  # ============================================================================

  networking.firewall = {
    allowedTCPPorts = [9757]; # WiVRn TCP
    allowedUDPPorts = [
      9757 # WiVRn UDP
      9758 # WiVRn control
      9759 # Lighthouse tracking
      27031 # SteamVR
      27036 # SteamVR discovery
    ];
  };
}
