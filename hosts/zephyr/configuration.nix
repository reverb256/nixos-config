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
    # OpenClaw now managed via nix-openclaw in home.nix
    ../../modules/stability-matrix.nix  # StabilityMatrix - Stable Diffusion package manager
  ];

  # ============================================================================
  # STABILITYMATRIX - Stable Diffusion Package Manager
  # ============================================================================

  programs.stability-matrix = {
    enable = true;
    enableCuda = true;  # NVIDIA GPU support (RTX 3090)
    dataDir = "/home/j_kro/.stabilitymatrix";
  };

  # ============================================================================
  # MINING MONITOR PLASMOID - Multi-node GPU/CPU monitor widget
  # ============================================================================

  programs.mining-plasmoid = {
    enable = true;
  };

  # ============================================================================
  # LOCALSEND - Cross-platform local file sharing (AirDrop alternative)
  # ============================================================================

  programs.localsend = {
    enable = true;
    openFirewall = true;  # Opens TCP/UDP port 53317 for receiving files
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
    # ============================================================================
    # LM STUDIO WITH GPU SUPPORT (CUDA + Vulkan)
    # ============================================================================
    # Custom package that properly wraps LM Studio with CUDA/Vulkan support
    # Based on: https://github.com/NixOS/nixpkgs/issues/340346
    # The default nixpkgs lmstudio only includes ocl-icd (OpenCL), missing CUDA/Vulkan
    # 
    # KEY FIX: Use extraBwrapArgs to mount /run/opengl-driver so libcuda.so is accessible!
    
    (let
      version = "0.4.2-2";
      src = pkgs.fetchurl {
        url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
        hash = "sha256-JxGlqgsuLcW81mOIcntVFSHv19zSFouIChgz/egc+J0=";
      };
      
      # Extract the AppImage contents
      appimageContents = pkgs.appimageTools.extractType2 {
        inherit version src;
        pname = "lm-studio";
      };
    in pkgs.buildFHSEnv {
      name = "lm-studio";
      
      # Include CUDA/Vulkan libraries inside the FHS environment
      targetPkgs = pkgs: with pkgs; [
        # OpenCL
        ocl-icd
        
        # CUDA Runtime libraries
        cudaPackages.cuda_cudart
        cudaPackages.libcublas
        cudaPackages.libcufft
        cudaPackages.libcusparse
        cudaPackages.libcusolver
        cudaPackages.cudnn
        
        # Vulkan support
        vulkan-loader
        vulkan-headers
        
        # Graphics libraries
        libGL
        libglvnd
        
        # Additional dependencies
        stdenv.cc.cc.lib
        glib
        nss
        nspr
        dbus
        libdrm
        fontconfig
        freetype
        zlib
        alsa-lib
        cups
        expat
        libxkbcommon
        wayland
      ];
      
      # CRITICAL: Mount /run/opengl-driver so NVIDIA driver libraries are accessible!
      # This is the key fix - libcuda.so lives in /run/opengl-driver/lib
      extraBwrapArgs = [
        "--ro-bind /run/opengl-driver /run/opengl-driver"
        "--ro-bind /run/agenix.d /run/agenix.d"
      ];
      
      # Run the AppImage directly inside FHS environment
      # --no-sandbox is critical for GPU access
      runScript = "${pkgs.bash}/bin/bash -c 'exec ${appimageContents}/AppRun --no-sandbox \"$@\"' --";
      
      # Set GPU environment variables
      profile = ''
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export CUDA_VISIBLE_DEVICES=0
        export VK_ICD_FILENAMES="/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
        export XDG_DATA_DIRS="/run/opengl-driver/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
      '';
      
      extraInstallCommands = ''
        # Install the CLI tool (lms)
        mkdir -p $out/bin
        cat > $out/bin/lms << 'LMS_EOF'
#!/bin/bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export CUDA_VISIBLE_DEVICES=0
export LD_LIBRARY_PATH="/run/opengl-driver/lib:/run/opengl-driver/lib64''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export VK_ICD_FILENAMES="/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
exec ${pkgs.steam-run}/bin/steam-run ${appimageContents}/resources/app/.webpack/lms "$@"
LMS_EOF
        chmod +x $out/bin/lms
        
        # Install desktop file
        mkdir -p $out/share/applications
        cat > $out/share/applications/lm-studio.desktop << 'DESKTOP_EOF'
[Desktop Entry]
Name=LM Studio
Comment=Run local LLMs with GPU acceleration
Exec=lm-studio %U
Icon=lm-studio
Categories=Development;IDE;
Terminal=false
Type=Application
DESKTOP_EOF
        
        # Install icon
        mkdir -p $out/share/icons/hicolor/0x0/apps
        cp ${appimageContents}/usr/share/icons/hicolor/0x0/apps/lm-studio.png $out/share/icons/hicolor/0x0/apps/
      '';
    })
  ];
}
