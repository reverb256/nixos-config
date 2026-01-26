# Zephyr Host Configuration - Steam + Wayland Optimized
# 10.1.1.110 - Master Workstation (32 cores, RTX 3090) - Steam Compatible
{...}: {
  imports = [
    # Host-specific hardware
    ./hardware-configuration.nix
    # Steam-compatible desktop and gaming
    ../../modules/desktop.nix
    ../../modules/steam-wayland-robust.nix
    # OpenAgents Control
    ../../modules/openagents-control.nix
    # Remove gaming.nix - too aggressive for Steam compatibility
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
  # STEAM-COMPATIBLE KERNEL PARAMETERS (Conservative for Wayland)
  # ============================================================================
  
  boot.kernelParams = [
    # Steam-specific optimizations
    "fsync.enable=1"
    
    # NVIDIA Wayland support (desktop module handles nvidia-drm.modeset=1)
    "threadirqs"
    
    # Enhanced NVIDIA RTX 3090 optimizations (Steam-compatible)
    "nvidia.NVreg_RegistryDwords=PerfLevelSrc=0x2222"
    "nvidia.NVreg_UsePageAttributeTable=1" # Better memory management
    "nvidia.NVreg_EnableResizableBar=1" # Resizable BAR for RTX 3090
    "nvidia-uvm/uvm_disable_huge_pages=1" # Fix SteamVR compatibility
    
    # Conservative CPU optimizations (removed aggressive Steam-breaking params)
    "amd_pstate=active"
    "mitigations=off"
    "transparent_hugepage=madvise"
    "numa_balancing=disable"
    "nowatchdog"
    
    # Safe I/O optimizations
    "elevator=none"
    
    # REMOVED: These break Steam process management
    # "isolcpus=managed_applications" - INTERFERES WITH STEAM
    # "nohz_full=1-15" - BREAKS STEAM PROCESS MANAGEMENT  
    # "rcu_nocbs=1-15" - BREAKS STEAM PROCESS MANAGEMENT
  ];

  # ============================================================================
  # MINING CONFIGURATION (Steam-aware - pauses during gaming)
  # ============================================================================
  
  # Note: Smart mining pause is handled by steam-wayland-robust.nix
  # It will automatically pause mining when Steam/VR games are detected
  services.mining.enable = true;
  services.mining.xmrig.enable = true;
  services.mining.xmrig.threads = 16;
  services.mining.xmrig.pool = "xtm-rx-us.kryptex.network:8038";
  services.mining.xmrig.wallet = "krxXVNVMM7.zephyr";
  
  # Steam-optimized lolminer configuration
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
  # FIREWALL (VR ports for WiVRn streaming - Steam-compatible)
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