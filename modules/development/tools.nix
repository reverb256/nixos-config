# Development Tools Module
# General development tools and utilities (expanded from XNM1)
{ pkgs, ... }: {
  # ============================================================================
  # ENVIRONMENT MANAGEMENT
  # ============================================================================
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  environment.systemPackages = with pkgs; [
    # Version Control
    git
    git-lfs
    gh
    lazygit
    glab

    # Git alternative and extras
    jujutsu # Git-compatible VCS (jj)
    jjui # Jujutsu UI

    # Git security and helpers
    gitleaks # Secret scanner
    pass-git-helper # Git credential integration
    license-generator # Generate license files
    git-ignore # Generate .gitignore files

    # Command runner
    just # Just command runner (like make)

    # Search & Navigation
    ripgrep
    fzf
    fd
    broot
    zoxide

    # File Management
    eza
    bat
    duf
    dust
    ncdu

    # Process Monitoring
    btop
    iotop
    htop

    # Network Tools
    curl
    wget
    httpie
    restic

    # Diff Tools
    delta
    diff-so-fancy
    meld

    # Documentation
    tealdeer
    tldr
    man-pages
    mandoc

    # Compression
    zip
    unzip
    p7zip
    rar

    # Archive tools
    atool
    lrzip

    # ============================================================================
    # BUILD TOOLS (from XNM1)
    # ============================================================================
    # Linkers and compilers
    mold # Modern linker (faster than ld)
    gcc
    clang
    lld # LLVM linker
    lldb # LLVM debugger
    musl # C standard library

    # Java
    jdk11

    # ============================================================================
    # DEVELOPMENT FRAMEWORKS
    # ============================================================================
    dioxus-cli # Rust GUI framework
    trunk # Rust WASM bundler

    # Development environments
    devenv # Nix-based dev environments

    # Version manager (asdf replacement)
    mise

    # ============================================================================
    # DATABASE TOOLS (from XNM1)
    # ============================================================================
    sqlx-cli # SQLx command line
    surrealdb # Distributed database
    surrealdb-migrations
    surrealist # SurrealDB GUI

    # ============================================================================
    # NETWORK / API TOOLS (from XNM1)
    # ============================================================================
    hurl # HTTP testing tool
    grex # Regex generator

    # ============================================================================
    # MISC UTILITIES
    # ============================================================================
    jq
    jo
    yq
    bc
    calc
    units
  ];
}
