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
    ../../modules/fish-starship.nix
    ../../modules/gaming.nix
    ../../modules/nvidia-wayland.nix
    ../../modules/garnix.nix
    ../../modules/tailscale.nix
    ../../modules/aistor-secrets.nix
    ../../modules/nix-cache-server.nix
    ../../modules/mcp-servers.nix
    ../../modules/nix-ld.nix
    ../../modules/mining.nix
    ../../modules/auto-update.nix
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
  services.nixos-auto-update.enable = true;

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
        powerLimit = 250;
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

  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "openrazer"];

  services.tailscale = {
    enable = true;
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "lms" ''
      #!/bin/bash
      cd /tmp
      export NVIDIA_DRIVER_PATH=/run/opengl-driver
      export NVIDIA_LIB_PATH=/run/opengl-driver/lib
      export NVIDIA_ICD_PATH=/run/opengl-driver/share/vulkan/icd.d
      export CUDA_PATH=/run/opengl-driver
      exec ${pkgs.steam-run}/bin/steam-run \
        --unshare-user-group \
        --bind "$NVIDIA_LIB_PATH:/usr/lib" \
        --bind "$NVIDIA_LIB_PATH:/usr/lib64" \
        --bind "$NVIDIA_LIB_PATH:/lib" \
        --bind "$NVIDIA_LIB_PATH:/lib64" \
        --bind "$NVIDIA_ICD_PATH:/etc/vulkan/icd.d" \
        ${pkgs.lmstudio}/bin/lms "$@"
    '')
    (pkgs.writeShellScriptBin "lm-studio" ''
      #!/bin/bash
      cd /tmp
      export NVIDIA_DRIVER_PATH=/run/opengl-driver
      export NVIDIA_LIB_PATH=/run/opengl-driver/lib
      export NVIDIA_ICD_PATH=/run/opengl-driver/share/vulkan/icd.d
      export CUDA_PATH=/run/opengl-driver
      exec ${pkgs.steam-run}/bin/steam-run \
        --unshare-user-group \
        --bind "$NVIDIA_LIB_PATH:/usr/lib" \
        --bind "$NVIDIA_LIB_PATH:/usr/lib64" \
        --bind "$NVIDIA_LIB_PATH:/lib" \
        --bind "$NVIDIA_LIB_PATH:/lib64" \
        --bind "$NVIDIA_ICD_PATH:/etc/vulkan/icd.d" \
        ${pkgs.lmstudio}/bin/lm-studio "$@"
    '')
  ];

  systemd.oomd.enable = true;
  systemd.coredump.enable = true;

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

  services.nix-cache-server = {
    enable = true;
    port = 8080;
  };
}
