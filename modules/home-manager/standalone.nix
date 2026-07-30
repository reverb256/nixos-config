{ config, lib, pkgs, inputs, hostName, vfioPkgs, ... }:

let
  hmLeaf = [
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
  ] ++ lib.optionals (hostName == "zephyr" || hostName == "sentry") [
    ./niri-config.nix
  ] ++ lib.optionals (hostName == "zephyr") [
    ./standalone-zephyr.nix
  ] ++ lib.optionals (hostName == "nexus") [
    ./standalone-nexus.nix
  ] ++ lib.optionals (hostName == "forge") [
    ./standalone-forge.nix
  ] ++ lib.optionals (hostName == "sentry") [
    ./standalone-sentry.nix
  ];
in {
  imports = hmLeaf;

  home.stateVersion = "26.05";
  home.pointerCursor.enable = true;

  programs.bash = {
    enable = true;
    initExtra = ''
      if [ -f ~/.bashrc ]; then
        source ~/.bashrc
      fi
    '';
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set -g fish_greeting
      fish_add_path /home/j_kro/bin
    '';
    loginShellInit = ''
      if test "$XDG_VTNR" = "1" -a -z "$WAYLAND_DISPLAY"
        exec uwsm start -F -- niri
      end
    '';
    shellAliases = {
      ll = "ls -la";
      la = "ls -A";
      l = "ls -CF";
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
    };
  };

  programs.git = {
    enable = true;
    userName = "Jeremy Kroeker";
    userEmail = "jkroeker@proton.me";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      core.autocrlf = "input";
    };
  };

  programs.ssh = {
    enable = true;
    extraConfig = ''
      Host 10.1.1.*
        StrictHostKeyChecking no
        UserKnownHostsFile ~/.ssh/known_hosts
    '';
  };

  programs.gpg.enable = true;
  home.sessionVariables.BAT_THEME = "base16-stylix";
  systemd.user.sessionVariables.HF_TOKEN = "/run/secrets/huggingface-token";

  _module.args.hostName = lib.mkDefault hostName;
  _module.args.vfioPkgs = lib.mkDefault vfioPkgs;
  _module.args.inputs = lib.mkDefault inputs;
}
