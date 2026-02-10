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
  ];

  networking = {
    hostName = "zephyr";

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

    # Additional services for AI and automation (disabled until modules are properly set up)
    # n8n = {
    #   enable = true;
    #   port = 5678;
    #   host = "0.0.0.0";
    #   openFirewall = true;
    # };
    # stable-diffusion = {
    #   enable = true;
    #   port = 7860;
    #   host = "0.0.0.0";
    #   gpuType = "cuda";  # Use CUDA for NVIDIA RTX 3090
    #   cmdOptions = [
    #     "--xformers"
    #     "--opt-split-attention"
    #     "--medvram"
    #   ];
    #   openFirewall = true;
    # };
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

  # Environment variables for CUDA and Vulkan accessibility
  environment.variables = {
    # NVIDIA-specific variables
    NVIDIA_DRIVER_PATH = "/run/opengl-driver";
    NVIDIA_LIB_PATH = "/run/opengl-driver/lib";
    NVIDIA_ICD_PATH = "/run/opengl-driver/share/vulkan/icd.d";

    # CUDA variables
    CUDA_PATH = "/run/opengl-driver";
    CUDA_HOME = "/run/opengl-driver";

    # Vulkan variables
    VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json";

    # Library path enhancement for CUDA detection
  };
  environment.variables.LD_LIBRARY_PATH = pkgs.lib.mkForce "/run/opengl-driver/lib:/run/opengl-driver/lib64";

  boot.kernel.sysctl = {
    "vm.swappiness" = 80;
    "vm.overcommit_ratio" = 90;
  };

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
      export NVIDIA_DRIVER_PATH=/run/opengl-driver
      export NVIDIA_LIB_PATH=/run/opengl-driver/lib
      export NVIDIA_ICD_PATH=/run/opengl-driver/share/vulkan/icd.d

      # Enhance library path for CUDA detection
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver/lib64:$LD_LIBRARY_PATH"
      export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json

      # Use steam-run with enhanced bindings for maximum compatibility
      exec ${pkgs.steam-run}/bin/steam-run \
        --unshare-user-group \
        --setenv=__NV_PRIME_RENDER_OFFLOAD=1 \
        --setenv=__GLX_VENDOR_LIBRARY_NAME=nvidia \
        --setenv=__VK_LAYER_NV_optimus=NVIDIA_only \
        --setenv=CUDA_PATH=/run/opengl-driver \
        --setenv=CUDA_HOME=/run/opengl-driver \
        --setenv=NVIDIA_DRIVER_PATH=/run/opengl-driver \
        --setenv=NVIDIA_LIB_PATH=/run/opengl-driver/lib \
        --setenv=LD_LIBRARY_PATH=/run/opengl-driver/lib:/run/opengl-driver/lib64 \
        --setenv=VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json \
        --bind "/run/opengl-driver/lib:/usr/lib" \
        --bind "/run/opengl-driver/lib64:/usr/lib64" \
        --bind "/run/opengl-driver/lib:/lib" \
        --bind "/run/opengl-driver/lib64:/lib64" \
        --bind "/run/opengl-driver/share/vulkan/icd.d:/etc/vulkan/icd.d" \
        --bind "/run/opengl-driver/bin:/usr/bin" \
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
      export NVIDIA_DRIVER_PATH=/run/opengl-driver
      export NVIDIA_LIB_PATH=/run/opengl-driver/lib
      export NVIDIA_ICD_PATH=/run/opengl-driver/share/vulkan/icd.d

      # Enhance library path for CUDA detection
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver/lib64:$LD_LIBRARY_PATH"
      export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json

      # Use steam-run with enhanced bindings for maximum compatibility
      exec ${pkgs.steam-run}/bin/steam-run \
        --unshare-user-group \
        --setenv=__NV_PRIME_RENDER_OFFLOAD=1 \
        --setenv=__GLX_VENDOR_LIBRARY_NAME=nvidia \
        --setenv=__VK_LAYER_NV_optimus=NVIDIA_only \
        --setenv=CUDA_PATH=/run/opengl-driver \
        --setenv=CUDA_HOME=/run/opengl-driver \
        --setenv=NVIDIA_DRIVER_PATH=/run/opengl-driver \
        --setenv=NVIDIA_LIB_PATH=/run/opengl-driver/lib \
        --setenv=LD_LIBRARY_PATH=/run/opengl-driver/lib:/run/opengl-driver/lib64 \
        --setenv=VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json \
        --bind "/run/opengl-driver/lib:/usr/lib" \
        --bind "/run/opengl-driver/lib64:/usr/lib64" \
        --bind "/run/opengl-driver/lib:/lib" \
        --bind "/run/opengl-driver/lib64:/lib64" \
        --bind "/run/opengl-driver/share/vulkan/icd.d:/etc/vulkan/icd.d" \
        --bind "/run/opengl-driver/bin:/usr/bin" \
        ${pkgs.lmstudio}/bin/lm-studio "$@"
    '')

    # Keep original wrappers as fallback
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

    # Additional CUDA packages for better compatibility
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    opencl-headers
    vulkan-tools
    vulkan-validation-layers
  ];
}
