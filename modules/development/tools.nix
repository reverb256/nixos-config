{pkgs, ...}: {
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
    chromium

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
    surrealist

    hurl
    grex

    jq
    jo
    yq
    bc
    calc
    units

    graphviz
    mermaid-cli
    gitea
  ];
}
