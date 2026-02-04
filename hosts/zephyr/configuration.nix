# Zephyr Host Configuration - MINIMAL NVIDIA + Wayland
# 10.1.1.110 - Master Workstation (32 cores, RTX 3090)
{
  config,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/desktop.nix
    ../../modules/gaming.nix
    ../../modules/nvidia-wayland.nix
    ../../modules/garnix.nix
    ../../modules/openclaw-declarative-container.nix
    ../../modules/tailscale.nix
    ../../modules/lmstudio-docker.nix
    ../../modules/aistor-secrets.nix
    ../../modules/mcp-servers.nix
    ../../modules/nix-ld.nix
    ../../modules/mining.nix
    ../../modules/flatpak-steam.nix
  ];

  networking.hostName = "zephyr";

  services.xserver.videoDrivers = ["nvidia"];
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;

  hardware.nvidia.wayland = {
    enable = true;
    openModules = true;
    sddmWayland = true;
  };

  boot.kernelParams = [
    "nvidia_drm.modeset=1"
    "nvidia_drm.fbdev=1"
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

  hardware.nvidia.powerManagement.enable = true;
  hardware.nvidia.powerManagement.finegrained = false;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  programs.gamemode.enable = true;

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

  systemd.services.display-manager.restartIfChanged = false;
  systemd.services.sddm.restartIfChanged = false;
  services.logind.settings.Login.KillUserProcesses = false;

  services.garnix.enable = true;

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
      wallet = "krxXVNVMM7.zephyr";
      nvidia = {
        enable = true;
        devices = "0";
      };
    };
  };

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

  networking.hosts = {
    "10.1.1.110" = ["zephyr"];
    "10.1.1.120" = ["nexus"];
    "10.1.1.130" = ["forge"];
    "10.1.1.140" = ["sentry"];
  };

  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker"];

  services.openclaw.declarative = {
    enable = true;
    image = "ghcr.io/openclaw/openclaw:latest";
    port = 18789;
    apiPort = 18790;
    stateDir = "/var/lib/openclaw";
    dataDir = "/var/lib/openclaw/data";
    configDir = "/etc/openclaw";
    memory = "2G";
    cpuShares = 512;
    gatewayMode = "local";
    gatewayBind = "100.81.182.5";
    environmentFile = "/run/agenix/openclaw-env";
    enableLegacyEnv = true;
  };

  services.tailscale = {
    enable = true;
  };

  services.lmstudio-docker = {
    enable = true;
    daemonPort = 1234;
    modelsDir = "/home/j_kro/.local/share/lm-studio/models";
    dataDir = "/home/j_kro/.local/share/lm-studio/data";
  };

  services.mcp-servers = {
    enable = true;
    servers.playwright.enable = true;
  };

  networking.firewall = {
    allowedTCPPorts = [9757 18789 18790];
    allowedUDPPorts = [
      9757
      9758
      9759
      27031
      27036
    ];
    interfaces."tailscale0".allowedTCPPorts = [18789 18790];
  };

  boot.kernel.sysctl = {
    "vm.swappiness" = 80;
    "vm.overcommit_ratio" = 90;
  };
}
