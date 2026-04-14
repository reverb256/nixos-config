# LSP and Development Tools Module
# Language servers and development tools for multiple languages
{
  pkgs,
  lib,
  ...
}:
{
  # Install LSP servers and development tools
  environment.systemPackages = with pkgs; [

    # LANGUAGE SERVERS & LSP

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
    typescript
    typescript-language-server
    vscode-langservers-extracted
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
    # Lua (lua-language-server in programming-languages.nix)
    stylua
    # YAML
    yaml-language-server
    yamllint
    # JSON
    vscode-json-languageserver
    # Markdown
    markdownlint-cli
    # Bash/Shell
    bash-language-server
    shellcheck
    shfmt
    # SQL
    sqls
    # C/C++
    clang-tools
    cmake
    ninja
    gnumake
    # Go (gopls in programming-languages.nix)
    go-tools
    gotools
    # Terraform
    terraform-ls
    tflint
    # Dockerfile
    dockerfile-language-server
    hadolint

    # DEVELOPMENT TOOLS (unique to this module)
    # Duplicated packages live in development/tools.nix:
    #   git, git-lfs, lazygit, gh, ripgrep, fzf, fd, tealdeer, zoxide,
    #   curl, wget, httpie, restic, jq, yq, bat, eza, duf, dust,
    #   delta, man-pages, neovim, helix, gdb, hyperfine, sqlite,
    #   strace, ltrace, perf-tools

    # Build tools not in tools.nix
    meson
    # Container tools
    dive # Docker image explorer
    lazydocker # Docker/Podman TUI
    # Database
    postgresql
  ];

  # DEVELOPMENT ENVIRONMENT VARIABLES

  # Use common environment variables module for EDITOR/VISUAL
  environment.common.development.editor = lib.mkDefault "nvim";
  # Development-tool-specific environment variables
  environment.sessionVariables = {
    # Language-specific overrides
    PYTHONPATH = "/var/lib/ai/python";
    # Go
    GOPATH = "$HOME/go";
    GOBIN = "$HOME/go/bin";
    # Rust
    CARGO_HOME = "$HOME/.cargo";
    # Git configuration
    GIT_CONFIG_SYSTEM = "/etc/gitconfig-safe-nixos.conf";
  };

  # GIT CONFIGURATION

  # System gitconfig with safe.directory for ai-inference user
  # Git 2.35+ requires explicit approval for owned repos
  # Use tmpfiles to create override config
  systemd.tmpfiles.rules = [
    "f /etc/gitconfig-safe - - - - -"
    "w /etc/gitconfig-safe - - - - [safe] /etc/nixos"
  ];
}
