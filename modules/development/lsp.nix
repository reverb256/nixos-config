# LSP and Development Tools Module
# Language servers and development tools for multiple languages
{pkgs, lib, ...}: {
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
    alejandra # Nix formatter
    statix # Nix linter
    deadnix # Nix dead code finder
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
    GOBIN = "$HOME/go/bin";

    # Rust
    CARGO_HOME = "$HOME/.cargo";
  };

  # ============================================================================
  # GIT CONFIGURATION
  # ============================================================================

  # System gitconfig with safe.directory for ai-inference user
  # Git 2.35+ requires explicit approval for owned repos
  # Note: Don't use programs.git.config as it overrides environment.etc
  environment.etc."gitconfig".text = ''
    [init]
      defaultBranch = main
    [user]
      email = j_kro@zephyr
      name = j_kro
    [safe]
      directory = /etc/nixos
  '';
}
