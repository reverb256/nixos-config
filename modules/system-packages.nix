{
  pkgs,
  lib,
  inputs ? null,
  ...
}: {
  # Centralized SYSTEM packages - only packages needed by system services
  # User packages belong in home.nix
  environment.systemPackages =
    (lib.optionals (inputs != null && inputs ? kimi-cli) [
      inputs.kimi-cli.packages.x86_64-linux.default
    ])
    ++ (with pkgs; [
      # ============================================================================
      # SYSTEM UTILITIES
      # Needed by system services, scripts, or all users
      # ============================================================================
      ripgrep
      fd
      parallel
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

      # Gaming tools
      gamescope
      mangohud
      goverlay
      xrizer
      opencomposite
      vulkan-validation-layers
      vulkan-headers
      dxvk
      wine
      winetricks

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
      colmena
      home-manager

      # ============================================================================
      # DESKTOP ENVIRONMENT SUPPORT
      # KDE Plasma and Wayland system packages
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
      nvtopPackages.full
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
      xorg.xrdb
      xorg.xrandr
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
    ]);
}
