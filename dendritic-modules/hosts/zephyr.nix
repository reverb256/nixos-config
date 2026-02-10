# Zephyr Host Configuration
# 10.1.1.110 - Master Workstation (32 cores, RTX 3090)
{lib, ...}:
with lib; {
  networking.hostName = "zephyr";

  # NVIDIA-specific kernel parameters
  boot.kernelParams = [
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "split_lock_detect=off"
    "nvidia.NVreg_EnableResizableBar=1"
    "nvidia.NVreg_EnableGpuFirmware=1"
    "threadirqs"
    "preempt=full"
    "processor.max_cstate=1"
    "intel_idle.max_cstate=1"
    "iommu=pt"
  ];

  # Display manager configuration
  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
    };
    defaultSession = "plasma";
    autoLogin = {
      enable = true;
      user = "j_kro";
    };
  };

  # Prevent session killing during rebuild
  systemd.services.display-manager.restartIfChanged = false;
  systemd.services.sddm.restartIfChanged = false;
  services.logind.settings.Login.KillUserProcesses = false;

  # Enable services
  services.garnix.enable = true;
  services.nixos-auto-update.enable = true;

  # Mining configuration
  services.mining = {
    enable = true;
    user = "mining";
    xmrig = {
      enable = true;
      threads = 16;
      pool = "xtm-rx-us.kryptex.network:8038";
      wallet = "krxXVNVMM7.zephyr";
    };
    lolminer = {
      enable = true;
      algorithm = "CR29";
      pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040";
      nvidia = {
        enable = true;
        devices = "0";
        powerLimit = 250;
      };
    };
  };

  # Static IP configuration
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
      ipv6.method = "auto";
    };
  };

  # Local hosts
  networking.hosts = {
    "10.1.1.110" = ["zephyr"];
    "10.1.1.120" = ["nexus"];
    "10.1.1.130" = ["forge"];
    "10.1.1.140" = ["sentry"];
  };

  # User groups
  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "openrazer" "tailscale"];

  # Nix cache server
  services.nix-cache-server = {
    enable = true;
    port = 8080;
  };

  # MCP servers
  services.mcp-servers = {
    enable = true;
    servers.playwright.enable = true;
  };

  # Firewall ports
  networking.firewall.allowedTCPPorts = [9757 18789 18790];
  networking.firewall.allowedUDPPorts = [9757 9758 9759 27031 27036];
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [18789 18790];

  # System tuning
  boot.kernel.sysctl = {
    "vm.swappiness" = 80;
    "vm.overcommit_ratio" = 90;
  };

  systemd.oomd.enable = true;
  systemd.coredump.enable = true;
}
