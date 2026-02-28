# LSP and Development Tools Module
# Language servers and development tools for multiple languages
{pkgs, ...}: {
  # Install LSP servers and development tools
  environment.systemPackages = with pkgs; [
    # ============================================================================
    # LANGUAGE SERVERS & LSP
    # ============================================================================

    # Rust
    rust-analyzer
    taplo # TOML

    # Python
    python312Packages.python-lsp-server
    python312Packages.black
    python312Packages.isort
    python312Packages.mypy
    python312Packages.ruff

    # JavaScript/TypeScript
    nodePackages.typescript
    nodePackages.typescript-language-server
    nodePackages.vscode-langservers-extracted
    nodePackages."@tailwindcss/language-server"
    eslint
    prettier

    # Nix
    nil # Nix language server
    nixd
    nixfmt
    nixpkgs-fmt

    # Lua
    lua-language-server
    stylua

    # YAML
    nodePackages.yaml-language-server
    yamllint

    # JSON
    nodePackages.vscode-json-languageserver

    # Markdown
    markdownlint-cli

    # Bash/Shell
    nodePackages.bash-language-server
    shellcheck
    shfmt

    # SQL
    sqls

    # C/C++
    clang-tools
    cmake
    ninja
    gnumake

    # Go
    gopls
    go-tools
    gotools

    # Terraform
    terraform-ls
    tflint

    # Dockerfile
    dockerfile-language-server
    hadolint

    # ============================================================================
    # DEVELOPMENT TOOLS
    # ============================================================================

    # Version control
    git
    git-lfs
    lazygit
    gh

    # Editing
    neovim
    helix

    # Search & navigation
    ripgrep
    fzf
    fd
    tealdeer
    zoxide

    # Build tools
    gnumake
    cmake
    meson
    ninja

    # Debugging
    gdb
    ltrace
    strace

    # Performance analysis
    perf-tools
    hyperfine

    # Network tools
    curl
    wget
    httpie
    restic

    # Database tools
    sqlite
    postgresql

    # Container tools
    dive # Docker image explorer
    lazydocker # Docker/Podman TUI

    # Documentation
    man-pages

    # Misc tools
    jq
    yq
    delta
    bat
    eza
    duf
    dust
  ];

  # ============================================================================
  # DEVELOPMENT ENVIRONMENT VARIABLES
  # ============================================================================

  environment.sessionVariables = {
    # Editor
    EDITOR = "nvim";
    VISUAL = "nvim";

    # Language-specific overrides
    PYTHONPATH = "/var/lib/ai/python";

    # Go
    GOPATH = "$HOME/go";
    GOBIN = "$GOPATH/bin";

    # Rust
    CARGO_HOME = "$HOME/.cargo";
  };

  # ============================================================================
  # GIT CONFIGURATION
  # ============================================================================

  programs.git = {
    enable = true;
    config = {
      # Common git settings can be set here if needed
      init.defaultBranch = "main";
    };
  };

  # ============================================================================
  # DEVELOPMENT SHELL ALIASES (via Fish in modules/shell/fish.nix)
  # ============================================================================
  #
  # Available in Fish shell:
  # - lgit: lazygit
  # - ldocker: lazydocker
  # - conf: cd to ~/.config
  #
  # ============================================================================

  # ============================================================================
  # NOTES FOR LANGUAGE SETUP
  # ============================================================================

  # **Rust Development:**
  # - Use modules/development/rust.nix for advanced toolchain
  # - rust-analyzer is pre-configured
  # - All cargo tools available (watch, expand, etc.)

  # **Python Development:**
  # - python-lsp-server for LSP support
  # - pyright for type checking
  # - black, isort, ruff for formatting/linting
  # - Install packages via nix-shell or venv

  # **JavaScript/TypeScript:**
  # - typescript-language-server for LSP
  # - eslint and prettier for linting/formatting
  # - Install packages via npm

  # **Nix Development:**
  # - nil and nixd for LSP
  # - nixfmt for formatting
  # - alejandra for alternative formatting

  # **Go Development:**
  # - gopls for LSP
  # - go-tools for utilities
  # - Standard Go toolchain

  # **Container Development:**
  # - Podman is configured in modules/system/security.nix
  # - lazydocker for container management
  # - dockerfile-language-server for Dockerfiles
  #
  # ============================================================================
}
