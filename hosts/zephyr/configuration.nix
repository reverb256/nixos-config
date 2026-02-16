# Zephyr Host Configuration - Master Workstation
# 10.1.1.110 - 32 cores, RTX 3090
# Features: Gaming + VR, Stability Matrix, Nix Cache Server, MCP Servers
{
  config,
  pkgs,
  ...
}: {
  imports = [
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # Common host imports (desktop, gaming, networking, etc.)
    ../../modules/common-host.nix

    # Host-specific GPU support
    ../../modules/nvidia-wayland.nix

    # Zephyr-specific modules
    ../../modules/stability-matrix.nix
    ../../modules/nix-cache-server.nix
    ../../modules/mcp-servers.nix
    ../../modules/aistor-secrets.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "zephyr";

  # ============================================================================
  # GAMING + VR (Full support - RTX 3090)
  # ============================================================================
  services.gaming = {
    enable = true;
    vr.enable = false; # WiVRn, SteamVR, OpenXR
  };

  # ============================================================================
  # STABILITY MATRIX - Stable Diffusion Package Manager
  # ============================================================================
  programs.stability-matrix = {
    enable = true;
    enableCuda = true;
    dataDir = "/home/j_kro/.stabilitymatrix";
  };

  # ============================================================================
  # MINING MONITOR PLASMOID
  # ============================================================================
  programs.mining-plasmoid.enable = true;

  # ============================================================================
  # LOCALSEND - Cross-platform file sharing
  # ============================================================================
  programs.localsend = {
    enable = true;
    openFirewall = true;
  };

  # ============================================================================
  # NETWORKING
  # ============================================================================
  networking = {
    networkmanager = {
      enable = true;
      ensureProfiles.profiles."Wired connection 1" = {
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

    firewall = {
      allowedTCPPorts = [9757 18789 18790];
      allowedUDPPorts = [9757 9758 9759 27031 27036];
      interfaces."tailscale0".allowedTCPPorts = [18789 18790];
    };
  };

  # ============================================================================
  # KERNEL - CachyOS x86_64-v3 for gaming (Zen 3 architecture)
  # ============================================================================
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v3;

  # ============================================================================
  # NVIDIA CONFIGURATION
  # ============================================================================
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
    "nvidia.NVreg_EnableResizableBar=1"
    "nvidia.NVreg_EnableGpuFirmware=1"
    "split_lock_detect=off"
    "threadirqs"
    "preempt=full"
    "processor.max_cstate=1"
    "intel_idle.max_cstate=1"
    "iommu=pt"
  ];

  # ============================================================================
  # DISPLAY MANAGER
  # ============================================================================
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

    # Mining configuration
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

  # ============================================================================
  # TAILSCALE ROUTING (Gateway for cluster)
  # ============================================================================
  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # ============================================================================
  # USER GROUPS
  # ============================================================================
  users.users.j_kro.extraGroups = ["plugdev" "audio" "input" "docker" "openrazer" "tailscale"];

  # ============================================================================
  # CUDA ENVIRONMENT
  # ============================================================================
  environment.variables = {
    CUDA_PATH = "/run/opengl-driver";
    CUDA_HOME = "/run/opengl-driver";
  };
  environment.variables.LD_LIBRARY_PATH = pkgs.lib.mkForce "/run/opengl-driver/lib:/run/opengl-driver/lib64";

  # ============================================================================
  # LM STUDIO (Custom build with GPU support)
  # ============================================================================
  environment.systemPackages = with pkgs; [
    (let
      version = "0.4.2-2";
      src = pkgs.fetchurl {
        url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
        hash = "sha256-JxGlqgsuLcW81mOIcntVFSHv19zSFouIChgz/egc+J0=";
      };
      appimageContents = pkgs.appimageTools.extractType2 {
        inherit version src;
        pname = "lm-studio";
      };
    in pkgs.buildFHSEnv {
      name = "lm-studio";
      targetPkgs = pkgs: with pkgs; [
        ocl-icd
        cudaPackages.cuda_cudart
        cudaPackages.libcublas
        cudaPackages.libcufft
        cudaPackages.libcusparse
        cudaPackages.libcusolver
        cudaPackages.cudnn
        vulkan-loader
        vulkan-headers
        libGL
        libglvnd
        stdenv.cc.cc.lib
        glib nss nspr dbus libdrm fontconfig freetype zlib alsa-lib cups expat libxkbcommon wayland
      ];
      extraBwrapArgs = [
        "--ro-bind /run/opengl-driver /run/opengl-driver"
        "--ro-bind /run/agenix.d /run/agenix.d"
      ];
      runScript = "${pkgs.bash}/bin/bash -c 'exec ${appimageContents}/AppRun --no-sandbox \"$@\"' --";
      profile = ''
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export CUDA_VISIBLE_DEVICES=0
        export VK_ICD_FILENAMES="/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
        export XDG_DATA_DIRS="/run/opengl-driver/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
      '';
      extraInstallCommands = ''
        mkdir -p $out/bin
        cat > $out/bin/lms << 'EOF'
#!/bin/bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export CUDA_VISIBLE_DEVICES=0
export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export VK_ICD_FILENAMES="/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
exec ${pkgs.steam-run}/bin/steam-run ${appimageContents}/resources/app/.webpack/lms "$@"
EOF
        chmod +x $out/bin/lms
        mkdir -p $out/share/applications
        cat > $out/share/applications/lm-studio.desktop << 'EOF'
[Desktop Entry]
Name=LM Studio
Comment=Run local LLMs with GPU acceleration
Exec=lm-studio %U
Icon=lm-studio
Categories=Development;IDE;
Terminal=false
Type=Application
EOF
        mkdir -p $out/share/icons/hicolor/0x0/apps
        cp ${appimageContents}/usr/share/icons/hicolor/0x0/apps/lm-studio.png $out/share/icons/hicolor/0x0/apps/
      '';
    })
  ];
}
