{ config, lib, pkgs, inputs, hostName, vfioPkgs, ... }:
let
  # Leaf HM modules that declare options directly at top level
  hmShared = [
    ./fish.nix
    ./starship.nix
    ./btop.nix
    ./wayland-tools.nix
    ./zen-browser.nix
    ./nixcord-config.nix
    ./mime-apps.nix
    ./mime-fix.nix
    ./caprine.nix
    ./opencode.nix
    ./firefox-pwa-apps.nix
    ./freebuff-desktop.nix
    ./alacritty.nix
    ./hermes-skin.nix
    ./icon-theme.nix
    ./dolphin.nix
    ./desktop-utilities.nix
    ./copyq.nix
    ./git.nix
    ./tmux.nix
    ./lazygit.nix
    ./tui-apps.nix
    ./editorconfig.nix
    ./noctalia-stylix.nix
    ./stylix-bridges.nix
    ./heal-stale-backups.nix
  ];

  hmDesktop = lib.optionals (hostName == "zephyr" || hostName == "sentry") [
    ./niri-config.nix
  ];

  hmHost = lib.optionals (hostName == "zephyr") [
    ./zephyr.nix
  ] ++ lib.optionals (hostName == "nexus") [
    ./nexus.nix
  ] ++ lib.optionals (hostName == "forge") [
    ./forge.nix
  ] ++ lib.optionals (hostName == "sentry") [
    ./sentry.nix
  ];
in {
  imports = hmShared ++ hmDesktop ++ hmHost;

  home.stateVersion = "26.05";
  home.pointerCursor.enable = true;

  # Propagate args into imported modules
  _module.args.hostName = lib.mkDefault hostName;
  _module.args.vfioPkgs = lib.mkDefault vfioPkgs;
  _module.args.inputs = lib.mkDefault inputs;
}
