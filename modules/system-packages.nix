{pkgs, lib, inputs ? null, ...}: {
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
      # ============================================================================
      pkgs.cudaPackages.cudatoolkit
      pkgs.cudaPackages.cudnn
      pkgs.cudaPackages.libcufft
      pkgs.cudaPackages.libcusparse
      pkgs.cudaPackages.libcutensor
      pkgs.python312Packages.torchWithCuda
      pkgs.python312Packages.tensorflowWithCuda
      pkgs.ollama
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
      yt-dlp

      # ============================================================================
      # DISPLAY MANAGEMENT
      # System display configuration tools
      # ============================================================================
      xorg.xrdb
      xorg.xrandr
      kanshi
      kdePackages.kscreen
      kdePackages.kio-extras

      # ============================================================================
      # WEB BROWSER SUPPORT
      # ============================================================================
      firefoxpwa

      # ============================================================================
      # OPENCL SUPPORT
      # ============================================================================
      ocl-icd
      libclc

      # ============================================================================
      # AI TOOLS (System-level)
      # These provide system-wide AI capabilities
      # ============================================================================
      (pkgs.writeShellScriptBin "kilo" ''
        exec ${pkgs.nodejs_22}/bin/npx @kilocode/cli "$@"
      '')
    ]);
}
