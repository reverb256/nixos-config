{pkgs, ...}: {
  # Centralized system packages for better maintainability
  environment.systemPackages = with pkgs;
    [
      # System utilities
      ripgrep
      fd
      fzf
      parallel # GNU parallel for running commands simultaneously
      htop # Traditional process monitor (complement to btop)
      neofetch # System information tool
      wget # Additional download tool

      # Network management
      networkmanager
      btop # Modern process monitor (mentioned by user)

      # Steam and gaming
      steam-run # Required for running dynamically linked executables
      pkgsi686Linux.glibc # 32-bit glibc for Steam compatibility

      # OpenCL support for AMD GPUs
      ocl-icd # OpenCL ICD loader
      libclc # OpenCL bitcode library for Mesa
      # rocm-opencl-runtime # ROCm OpenCL runtime - BROKEN in nixpkgs-unstable
      tmux # Terminal multiplexer

      # Networking and file transfer
      curl
      jq # JSON processor for mining monitor
      mosh # Mobile shell for roaming connections
      nmap # Network scanner
      netcat # Network utility
      socat # Bidirectional data transfer

      # Web browser PWA support
      firefoxpwa # Progressive Web App support for Firefox-based browsers

      # Version control and development
      git
      vim
      just # Command runner (already in user packages)

      # File system tools
      btrfs-progs # Btrfs filesystem utilities

      # Hardware detection and system info
      pciutils # lspci and other PCI utilities
      usbutils # lsusb and other USB utilities
      lshw # Hardware lister

      # Vulkan support for gaming
      vulkan-loader
      vulkan-tools

      # NVIDIA tools for GPU monitoring
      # nvidia_x11 # Removed - use hardware.nvidia instead

      # NEW: CUDA and ML support for RTX 3090
      pkgs.cudaPackages.cudatoolkit
      pkgs.cudaPackages.cudnn
      pkgs.cudaPackages.libcufft
      pkgs.cudaPackages.libcusparse
      pkgs.cudaPackages.libcutensor
      pkgs.python312Packages.torchWithCuda
      pkgs.python312Packages.tensorflowWithCuda
      pkgs.ollama
      # Additional CUDA libraries for LMStudio
      pkgs.cudaPackages.libcurand
      pkgs.cudaPackages.libcusolver
      pkgs.cudaPackages.libnvjpeg

      # NH (Nix Helper) - Robust NixOS management
      nh

      # Colmena - Multi-host deployment tool
      colmena

      # Desktop notifications for mining controls
      libnotify
      kdePackages.kdialog
      networkmanagerapplet # GTK NetworkManager tray applet

      # KDE Plasma integration (CRITICAL for window management)
      kdePackages.xdg-desktop-portal-kde # Essential for window tracking
      kdePackages.kdbusaddons # DBus integration for KDE
      kdePackages.kdeconnect-kde # KDE device integration
      kdePackages.plasma-systemmonitor # System monitoring widget

      # Wayland portal services (CRITICAL for LMStudio and app functionality)
      xdg-desktop-portal
      kdePackages.xdg-desktop-portal-kde

      # Flatpak and sandbox support
      flatpak

      # AI tools and packages (from nix profile)
      qwen-code
      opencode

      # Local AI/ML tools - DISABLED due to ROCm build failures in nixpkgs-unstable
      # pkgs.python3Packages.vllm # High-performance LLM inference engine - BROKEN with ROCm

      # OpenCode AI Agent packages (patched for bun version compatibility)
      # opencode only provides devShells, not packages

      # Kimi Code CLI - AI coding agent (from flake)
      # Note: Use 'nix run .#kimi' or install via 'nix profile install .#kimi'
    ]
    ++ [
      # Gaming and VR tools
      gamescope
      mangohud
      goverlay # Gamemode integration overlay
      xrizer # OpenVR compatibility for Steam games
      opencomposite # Alternative OpenVR compatibility

      # Vulkan support packages
      vulkan-loader
      vulkan-tools
      vulkan-validation-layers
      vulkan-headers

      # DXVK for DirectX to Vulkan translation (needed for AAGL games)
      dxvk
      wine
      winetricks

      # User profile packages (from nix profile)
      alejandra
      btop
      colmena
      deadnix
      fd
      fzf
      gemini-cli
      neovim
      nodejs_22
      opencode
      qwen-code
      ripgrep
      statix
      tmux
      vesktop
      lmstudio

      # Language servers and development tools (from nix profile)
      basedpyright # Python type checker
      bash-language-server # Bash LSP
      nodePackages.typescript-language-server # TypeScript LSP
      nixd # Nix LSP

      # Nix formatters and linters (from nix profile)
      alejandra
      deadnix
      statix

      # Cloud storage and networking
      rclone
      rclone-browser
      restic
      tailscale

      # Terminal and shell tools (from nix profile)
      fish
      gh # GitHub CLI
      gparted # Partition editor

      # SSH utilities (from nix profile)
      sshpass

      # Shell prompt and configuration (from nix profile)
      starship
      zoxide
      eza
      mise

      # Home Manager
      home-manager

      # Multimedia support for audiotube and Qt applications
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-libav

      # Video encoding and GPU acceleration packages
      nvidia-vaapi-driver
      vdpauinfo
      nvtopPackages.full

      # Video processing for yt-dlp and media playback
      ffmpeg
      yt-dlp

      # Anime Game Launchers (enabled via programs.anime-game-launcher in host config)
    ];
}
