# Fish Shell Configuration
{ config, lib, pkgs, ... }:
{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      # Initialize zoxide for smart cd
      if type -q zoxide
        zoxide init fish | source
      end

      # Set greeting to empty
      set -g fish_greeting ""
    '';
    shellAliases = {
      # List aliases - modern replacements
      ll = "eza -lh --group-directories-first --icons=auto";
      la = "eza -la --group-directories-first --icons=auto";
      l = "eza --group-directories-first --icons=auto";
      lt = "eza --tree --level=2 --long --icons --git";

      # NixOS aliases
      update = "sudo nixos-rebuild switch --flake /etc/nixos";
      build = "sudo nixos-rebuild build --flake /etc/nixos";
      try = "sudo nixos-rebuild test --flake /etc/nixos";

      # Git aliases
      g = "git";
      gs = "git status";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline -10";
    };
  };
}
