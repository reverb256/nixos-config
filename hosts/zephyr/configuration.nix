# Zephyr Host Configuration - MINIMAL NVIDIA + Wayland
# 10.1.1.110 - Master Workstation (32 cores, RTX 3090)
{
  config,
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
    ../../modules/networking.nix
    ../../modules/tailscale.nix
    ../../modules/aistor-secrets.nix
    ../../modules/nix-cache-server.nix
    ../../modules/mcp-servers.nix
    ../../modules/mining.nix
    ../../modules/auto-update.nix
    ../../modules/ssh.nix
    ../../modules/distributed-builds.nix
    ../../modules/storage-btrfs.nix
    ../../modules/mining-build-wrapper.nix
    ../../modules/quadlet-openclaw.nix  # OpenClaw cluster orchestration
  ];

  # ============================================================================
  # OPENCLAW - CLUSTER ORCHESTRATION
  # ============================================================================

  services.openclaw-quadlet = {
    enable = true;
    workspacePath = "/home/j_kro/workspace";
    authToken = "";  # Set via agenix or environment variable
    port = 18090;
    bindToLocalhost = true;
  };

  networking = {
    hostName = "zephyr";
    networkmanager.enable = true;

    networkmanager.ensureProfiles = {
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

    hosts = {
      "10.1.1.110" = ["zephyr"];
      "10.1.1.120" = ["nexus"];
      "10.1.1.130" = ["forge"];
      "10.1.1.140" = ["sentry"];
    };

    firewall = {
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
  };

  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;

    wayland = {
      enable = true;
      openModules = true;
      sddmWayland = true;
    };

    powerManagement.enable = true;
    powerManagement.finegrained = false;
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

  services = {
    xserver.videoDrivers = ["nvidia"];

    displayManager = {
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

    logind.settings.Login.KillUserProcesses = false;

    garnix.enable = true;
    nixos-auto-update.enable = true;

    mining = {
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

    tailscale.enable = true;

    mcp-servers = {
      enable = true;
      servers.playwright.enable = true;
    };

    nix-cache-server = {
      enable = true;
      port = 8080;
    };

  };

  systemd = {
    services = {
      display-manager.restartIfChanged = false;
      sddm.restartIfChanged = false;
    };

    oomd.enable = true;
    coredump.enable = true;
  };

  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "openrazer" "tailscale"];

  # ============================================================================
  # TAILSCALE - Secure mesh VPN
  # ============================================================================
  # Routing features configured via tailscaled environment
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # Environment variables for CUDA accessibility
  environment.variables = {
    # CUDA variables
    CUDA_PATH = "/run/opengl-driver";
    CUDA_HOME = "/run/opengl-driver";

    # Vulkan variables

    # Library path enhancement for CUDA detection
  };
  environment.variables.LD_LIBRARY_PATH = pkgs.lib.mkForce "/run/opengl-driver/lib:/run/opengl-driver/lib64";

  # boot.kernel.sysctl moved to shared configuration.nix
  # vm.swappiness = 60 (gaming optimized)
  # vm.overcommit_ratio = 90 (shared config)

  environment.systemPackages = with pkgs; [
    # Enhanced LM Studio wrappers with proper GPU detection environment
    (pkgs.writeShellScriptBin "lms-enhanced" ''
      #!/bin/bash
      cd /tmp

      # Set environment variables for GPU detection
      export __NV_PRIME_RENDER_OFFLOAD=1
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      export __VK_LAYER_NV_optimus=NVIDIA_only

      # Set CUDA environment
      export CUDA_PATH=/run/opengl-driver
      export CUDA_HOME=/run/opengl-driver

      # Use steam-run for maximum compatibility
      exec ${pkgs.steam-run}/bin/steam-run \
        --unshare-user-group \
        --setenv=__NV_PRIME_RENDER_OFFLOAD=1 \
        --setenv=__GLX_VENDOR_LIBRARY_NAME=nvidia \
        --setenv=__VK_LAYER_NV_optimus=NVIDIA_only \
        ${pkgs.lmstudio}/bin/lms "$@"
    '')

    (pkgs.writeShellScriptBin "lm-studio-enhanced" ''
      #!/bin/bash
      cd /tmp

      # Set environment variables for GPU detection
      export __NV_PRIME_RENDER_OFFLOAD=1
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      export __VK_LAYER_NV_optimus=NVIDIA_only

      # Set CUDA environment
      export CUDA_PATH=/run/opengl-driver
      export CUDA_HOME=/run/opengl-driver

      # Use steam-run for maximum compatibility
      exec ${pkgs.steam-run}/bin/steam-run \
        --unshare-user-group \
        --setenv=__NV_PRIME_RENDER_OFFLOAD=1 \
        --setenv=__GLX_VENDOR_LIBRARY_NAME=nvidia \
        --setenv=__VK_LAYER_NV_optimus=NVIDIA_only \
        --setenv=CUDA_PATH=/run/opengl-driver \
        --setenv=CUDA_HOME=/run/opengl-driver \
        --bind "/run/opengl-driver/bin:/usr/bin" \
        ${pkgs.lmstudio}/bin/lm-studio "$@"
    '')

    # LM Studio wrapper removed - duplicate of lms-enhanced

    # Additional CUDA packages for better compatibility
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    opencl-headers
    vulkan-tools
    vulkan-validation-layers
  ];
}
