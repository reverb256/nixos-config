# Home-Manager Shared Configuration
# Declarative home directory management across all NixOS hosts
#
# Scope: .config/* and dotfiles (NOT user data like ~/models, ~/projects)
# Data persistence: Handled by preservation module
# Per-host configs: Separate files for each host

{ config, lib, pkgs, ... }:
let
  inherit (lib) mkDefault mkIf;
in
{
  # Home-Manager is already imported in common-modules-list.nix
  # This module configures j_kro's declarative home

  home-manager.users.j_kro = { pkgs, ... }: {
    home.stateVersion = "26.05";

    # Shell configuration
    programs.bash = {
      enable = true;
      initExtra = ''
        # Home-manager integration
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

    # Git configuration
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

    # SSH configuration (managed by preservation, but tracked here)
    programs.ssh = {
      enable = true;
      extraConfig = ''
        Host 10.1.1.*
          StrictHostKeyChecking no
          UserKnownHostsFile ~/.ssh/known_hosts
      '';
    };

    # GPG configuration (managed by preservation)
    programs.gpg.enable = true;

    # Common .config entries (shared across hosts)
    xdg.configFile."alacritty/alacritty.yml".source = ./alacritty.yml;
    xdg.configFile."fastfetch/config.conf".source = ./fastfetch.conf;

    # Files in home directory (not .config)
    home.file.".screenrc".source = ./dotfiles/.screenrc;
    home.file.".gtkrc-2.0".source = ./dotfiles/.gtkrc-2.0;

    # Critical: Zen Browser is NOT managed here - it's in preservation module
    # because it contains crypto wallets that must survive generation rollback
  };
}