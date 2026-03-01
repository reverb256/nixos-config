{pkgs, lib, ...}: {
  # Centralized SYSTEM packages - only packages needed by system services
  # User packages belong in home.nix
  environment.systemPackages = with pkgs; [
    mlocate  # For locate command

    # ============================================================================
    # SYSTEM UTILITIES
    # Needed by system services, scripts, or all users
    # ============================================================================
    ripgrep
    fd
    parallel
    parallel-full
    htop
    neofetch
    wget
    curl
    jq
    mosh
    nmap
    netcat
    socat
    tmux
    # websocat - REMOVED

    # ============================================================================
    # NETWORK MANAGEMENT
    # System-level networking tools
    # ============================================================================
    networkmanager
    networkmanagerapplet

    # ============================================================================
    # VERSION CONTROL AND BUILD TOOLS
    # Required for system operations
    # ============================================================================
    git
    vim
    just

    # ============================================================================
    # SECRETS MANAGEMENT
    # ssh-to-age for agenix SSH key conversion
    # ============================================================================
    ssh-to-age

    # ============================================================================
    # FILE SYSTEM TOOLS
    # ============================================================================
    btrfs-progs

    # ============================================================================
    # HARDWARE DETECTION
    # Used by system scripts and hardware configuration
    # ============================================================================
    pciutils
    usbutils
    lshw

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
    # These provide the runtime libraries, not user tools
    # NOTE: PyTorch/TensorFlow/ollama moved to home-manager to avoid long builds
    # ============================================================================
    pkgs.cudaPackages.cudatoolkit
    pkgs.cudaPackages.cudnn
    pkgs.cudaPackages.libcufft
    pkgs.cudaPackages.libcusparse
    pkgs.cudaPackages.libcutensor
    pkgs.cudaPackages.libcurand
    pkgs.cudaPackages.libcusolver
    pkgs.cudaPackages.libnvjpeg

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
    # ============================================================================
    libnotify
    kdePackages.kdialog
    kdePackages.xdg-desktop-portal-kde
    kdePackages.kdbusaddons
    kdePackages.kdeconnect-kde
    kdePackages.plasma-systemmonitor
    xdg-desktop-portal
    flatpak

    # ============================================================================
    # MULTIMEDIA SUPPORT
    # System-wide multimedia libraries
    # ============================================================================
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav

    # ============================================================================
    # VIDEO AND GPU ACCELERATION
    # System video drivers and utilities
    # ============================================================================
    nvidia-vaapi-driver
    vdpauinfo
    # NOTE: nvtopPackages.full is in gaming.nix
    egl-wayland
    wayland-utils
    ffmpeg
    # yt-dlp  # MOVED to home.nix - user media tool

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
    # NOTE: firefoxpwa moved to home.nix to avoid Firefox compilation
    # ============================================================================
    # firefoxpwa  # MOVED to home.nix - requires Firefox which compiles from source

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
