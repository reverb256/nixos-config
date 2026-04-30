{
  pkgs,
  lib,
  ...
}: {
  environment.systemPackages = with pkgs; [
    rust-analyzer
    taplo
    python312Packages.python-lsp-server
    python312Packages.black
    python312Packages.isort
    python312Packages.mypy
    python312Packages.ruff
    typescript
    typescript-language-server
    vscode-langservers-extracted
    eslint
    prettier
    nil
    nixd
    alejandra
    statix
    deadnix
    nixfmt
    nixpkgs-fmt
    stylua
    yaml-language-server
    yamllint
    vscode-json-languageserver
    markdownlint-cli
    bash-language-server
    shellcheck
    shfmt
    sqls
    clang-tools
    cmake
    ninja
    gnumake
    go-tools
    gotools
    terraform-ls
    tflint
    dockerfile-language-server
    hadolint

    meson
    dive
    lazydocker
    postgresql
  ];

  environment.common.development.editor = lib.mkDefault "nvim";
  environment.sessionVariables = {
    # PYTHONPATH removed from session vars — was poisoning ai-inference-gateway systemd service.
    # If Python LSP needs extra paths, configure in editor LSP settings, not globally.
    # PYTHONPATH = "/var/lib/ai/python";
    GOPATH = "$HOME/go";
    GOBIN = "$HOME/go/bin";
    CARGO_HOME = "$HOME/.cargo";
    GIT_CONFIG_SYSTEM = "/etc/gitconfig-safe-nixos.conf";
  };

  systemd.tmpfiles.rules = [
    "f /etc/gitconfig-safe - - - - -"
    "w /etc/gitconfig-safe - - - - [safe] /etc/nixos"
  ];
}
