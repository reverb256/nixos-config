{pkgs, ...}: {
  # Centralized SYSTEM packages - only packages needed by system services
  # User packages belong in home.nix
  environment.systemPackages = with pkgs; [
    # ============================================================================
    # SYSTEM UTILITIES (unique to this module)
    # Duplicated packages live in development/tools.nix:
    #   ripgrep, fd, htop, btop, eza, bat, fzf, wget, curl, jq, jo, yq,
    #   git, just, bc, units, strace, ltrace, perf-tools, iotop, ncdu,
    #   rclone, zip, unzip, p7zip, rar
    # ============================================================================
    parallel
    parallel-full
    fastfetch
    mosh
    nmap
    netcat
    socat
    tmux
    xh # Modern HTTP debugging tool (curl alternative)
    hexdump # Binary file inspection
    xxd # Hex dump from Vim
    file # File type detection (enhanced)
    tree # Directory tree viewer

    # ============================================================================
    # NETWORK MANAGEMENT
    # System-level networking tools
    # ============================================================================
    networkmanager

    # ============================================================================
    # VERSION CONTROL AND BUILD TOOLS
    # git, just moved to development/tools.nix
    # ============================================================================
    vim
    hostname

    # ============================================================================
    # SECRETS MANAGEMENT
    # ssh-to-age for agenix SSH key conversion
    # ============================================================================
    ssh-to-age

    # ============================================================================
    # FILE SYSTEM TOOLS
    # rclone moved to development/tools.nix
    # ============================================================================
    btrfs-progs
    awscli2 # For S3 backup automation

    # ============================================================================
    # HARDWARE DETECTION
    # Used by system scripts and hardware configuration
    # ============================================================================
    pciutils
    usbutils
    lshw
    dmidecode # SMBIOS/BIOS hardware info
    hwinfo # Comprehensive hardware detection
    smartmontools # SMART disk monitoring (smartctl)

    # ============================================================================
    # DIAGNOSTIC AND DEBUGGING TOOLS
    # strace, ltrace, perf-tools, iotop moved to development/tools.nix
    # ============================================================================
    perf # Kernel performance analysis

    # ============================================================================
    # NETWORK DIAGNOSTICS
    # Advanced network troubleshooting and monitoring
    # ============================================================================
    ethtool # Network card configuration and diagnostics
    bmon # Bandwidth monitor (console-based)
    iftop # Interactive bandwidth monitoring
    tcpdump # Packet capture and analysis
    mtr # Network diagnostic (ping + traceroute hybrid)
    dnsutils # DNS lookup utilities (dig, nslookup)

    # ============================================================================
    # STORAGE AND FILE SYSTEM UTILITIES
    # Additional tools for storage management and data handling
    # ============================================================================
    parted # GPT partition management
    gptfdisk # GPT fdisk (for modern partitioning)
    # ncdu moved to development/tools.nix
    rsync # Fast file synchronization
    pv # Pipe viewer for monitoring data throughput
    progress # Coreutils progress viewer

    # ============================================================================
    # ARCHIVE AND COMPRESSION
    # zip, unzip, p7zip, rar moved to development/tools.nix
    # ============================================================================

    # ============================================================================
    # SCREEN AND SESSION MANAGEMENT
    # Terminal multiplexer alternatives
    # ============================================================================
    screen # Alternative terminal multiplexer

    # ============================================================================
    # GAMING SUPPORT
    # Steam and gaming libraries (configured in gaming.nix)
    # ============================================================================
    steam-run
    pkgsi686Linux.glibc

    # Vulkan support
    vulkan-loader
    vulkan-tools

    # Gaming tools - NOTE: gamescope, mangohud, goverlay, nvtop are in gaming.nix
    xrizer
    opencomposite
    vulkan-validation-layers
    vulkan-headers
    dxvk
    wine
    winetricks
    vkbasalt # Vulkan post-processing (CAS sharpening, FXAA)
    obs-studio-plugins.obs-vkcapture # Zero-copy OBS game capture

    # ============================================================================
    # PERIPHERAL SUPPORT
    # Razer and Corsair device management tools
    # Razer packages now handled by hardware.openrazer module
    # liquidctl - Cross-platform CLI for AIO coolers, PSUs, and Corsair Vengeance RAM
    # ============================================================================
    polychromatic # Graphical front-end for Razer devices
    razergenie # Qt application for configuring Razer devices
    razer-cli # Command-line interface for Razer devices
    ckb-next # Driver and configuration tool for Corsair devices
    headsetcontrol # For Corsair VOID headsets
    liquidctl # AIO cooler, PSU, and RAM RGB control

    # ============================================================================
    # CUDA AND ML LIBRARIES
    # System libraries for CUDA/ML workloads
    # NOTE: These packages are now managed by hardware.gpu-compute module
    # NOTE: cudatoolkit was causing cuda_compat dependency (Jetson-only package)
    # REMOVED: cudatoolkit, cudnn, libcufft, libcusparse, libcutensor, libcurand, libcusolver, libnvjpeg
    # The gpu-compute module provides cuda_cudart for basic CUDA runtime support
    # Re-add individual packages here if needed for specific ML workloads
    # ============================================================================
    # pkgs.cudaPackages.cudatoolkit  # REMOVED: pulls in broken cuda_compat (Jetson-only)
    # pkgs.cudaPackages.cudnn         # REMOVED: pulls in cuda_compat
    # ... other CUDA packages removed for same reason

    # ============================================================================
    # SYSTEM MANAGEMENT TOOLS
    # Required for system administration
    # ============================================================================
    nh
    home-manager
    # Colmena is managed via flake.nix (v0.5.0-pre with colmenaHive schema)

    # ============================================================================
    # DESKTOP ENVIRONMENT SUPPORT
    # KDE Plasma and Wayland system packages
    # NOTE: Removed qtstyleplugin-kvantum and qt6ct - they cause crashes with
    # Plasma 6 Wayland on NVIDIA. Using Breeze (native KDE style) instead.
    # NOTE: KDE GUI packages moved to plasma6.nix to avoid duplication
    # ============================================================================
    xdg-desktop-portal
    flatpak

    # ============================================================================
    # MULTIMEDIA SUPPORT
    # System-wide multimedia libraries
    # NOTE: GStreamer packages moved to wayland-common.nix (desktop GUI packages)
    # ============================================================================

    # ============================================================================
    # VIDEO AND GPU ACCELERATION
    # System video drivers and utilities
    # ============================================================================
    nvidia-vaapi-driver
    vdpauinfo
    # NOTE: nvtopPackages.full is in gaming.nix
    egl-wayland
    wayland-utils
    # yt-dlp  # MOVED to home.nix - user media tool
    localsend # Local network file sharing (AirDrop alternative)

    # NOTE: nvidia-smi and nvidia-settings are provided by the NVIDIA driver package
    # which is configured per-host in hosts/<hostname>/configuration.nix
    # Example: hardware.nvidia.package = pkgs.linuxPackages_zen.nvidiaPackages.beta;

    # ============================================================================
    # DISPLAY MANAGEMENT
    # System display configuration tools
    # ============================================================================
    xrdb
    xrandr
    # kanshi  # MOVED to home.nix - user display management tool
    kdePackages.kscreen
    kdePackages.kio-extras

    # ============================================================================
    # WEB BROWSER SUPPORT
    # firefoxpwa does not exist in current nixpkgs.
    # For PWA support with Zen Browser, use the "PWAs for Firefox" extension.
    # ============================================================================
    wl-clipboard # For screenshot-to-clipboard pipeline

    # ============================================================================
    # OPENCL SUPPORT
    # ============================================================================
    ocl-icd
    libclc

    # ============================================================================
    # AI TOOLS (System-level)
    # NOTE: User AI tools moved to home.nix
    # ============================================================================
    # (kilo wrapper moved to home.nix - requires user nodejs)
  ];
}
