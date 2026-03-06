# Terminal Module
# Terminal emulators, editors, and CLI tools from XNM1
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # ============================================================================
    # TERMINAL EMULATORS
    # ============================================================================
    wezterm # Wezterm terminal
    kitty # GPU-accelerated terminal
    cool-retro-term # Retro-style terminal

    # ============================================================================
    # EDITORS
    # ============================================================================
    helix # Modern modal editor (kakoune-inspired)

    # ============================================================================
    # SHELL & TERMINAL UTILITIES (from XNM1)
    # ============================================================================

    # Core utilities
    moreutils # Collection of unix tools
    file # File type detection
    upx # Executable packer

    # Terminal multiplexer
    zellij # Modern terminal multiplexer (tmux alternative)

    # File managers
    yazi # Modern terminal file manager (Rust)

    # Progress monitoring
    progress # Coreutils progress viewer
    noti # Notification tool for long commands
    procs # Modern ps replacement
    gping # Ping with graph

    # Benchmarking
    rewrk # HTTP benchmarking
    wrk2 # HTTP benchmarking
    hyperfine # Benchmarking tool

    # Documentation
    tealdeer # Fast tldr client
    mermaid-cli # Mermaid diagram generator

    # Social / posting
    posting # Mastodon/pleroma client

    # Process management
    process-compose # Process supervisor/manager

    # Terminal recording
    asciinema # Terminal recorder
    asciinema-agg # Asciinema GIF generator

    # File transfer
    aria2 # Download utility
    croc # File transfer tool
    magic-wormhole-rs # Secure file transfer

    # DNS tools
    doggo # Modern DNS client

    # File operations
    sd # Intuitive find & replace
    ouch # Compression/decompression
    trash-cli # Trash commands

    # Code statistics
    tokei # Code statistics (like cloc)

    # Hex viewers
    hexyl # Hex viewer

    # Markdown
    mdcat # Markdown cat
    pandoc # Document converter

    # Directory listings
    lsd # ls replacement

    # Process info
    lsof # List open files

    # Image viewers (terminal)
    viu # Terminal image viewer
    chafa # Terminal graphics

    # Tree tools
    tre-command # Tree command (Rust)

    # Journaling
    jrnl # Journaling tool

    # Testing/fake data
    python313Packages.faker # Fake data generator

    # Fun/eye candy
    cmatrix # Matrix screensaver
    pipes-rs # Pipes screensaver
    rsclock # Retro clock
    cava # Audio visualizer
    figlet # ASCII art text
    lolcat # Rainbow text
    cbonsai # Bonsai tree generator
  ];
}
