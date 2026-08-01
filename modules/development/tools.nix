{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  environment.systemPackages = with pkgs; [
    git
    git-lfs
    gh
    lazygit
    glab

    jujutsu
    jjui

    gitleaks
    pass-git-helper
    license-generator
    git-ignore

    just

    ripgrep
    fzf
    fd
    broot
    zoxide

    eza
    bat
    duf
    dust
    ncdu

    btop
    iotop
    htop

    curl
    wget
    httpie
    restic
    rclone

    delta
    diff-so-fancy
    meld

    tealdeer
    tldr
    man-pages
    mandoc

    zip
    unzip
    p7zip
    rar

    atool
    lrzip

    mold
    gcc
    clang
    lld
    lldb
    musl

    jdk11

    dioxus-cli
    trunk

    mise

    sqlx-cli
    surrealdb
    surrealdb-migrations

    hurl
    grex

    jq
    jo
    yq
    bc
    calc
    units

    graphviz
    gitea
    # Heavy GUI/browser tooling — excluded from headless sentry (usb-rescue
    # recovery host: monitoring + Vulkan AI only). chromium + mermaid-cli pull
    # the full chromium-unwrapped build (~hours on nexus); surrealist (Tauri
    # SurrealDB GUI) pulls webkitgtk. Desktop hosts keep all three; zephyr
    # additionally re-adds mermaid-cli in its host config.
  ] ++ lib.optionals (config.networking.hostName != "sentry") [
    chromium
    mermaid-cli
    surrealist
  ];
}
