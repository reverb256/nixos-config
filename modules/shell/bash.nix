{pkgs, ...}: {
  programs.bash = {
    enable = true;

    promptInit = ''
      if [ -f "${pkgs.starship}/bin/starship" ]; then
        eval "$(${pkgs.starship}/bin/starship init bash)"
      fi
    '';

    interactiveShellInit = ''
      export EDITOR=nvim
      export VISUAL=nvim
      export TZ=America/Winnipeg

      export HISTSIZE=100000
      export HISTFILESIZE=100000
      export HISTCONTROL=ignoreboth:erasedups
      shopt -s histappend

      shopt -s autocd
      shopt -s cdspell
      shopt -s dirspell

      shopt -s checkwinsize

      if command -v zoxide &>/dev/null; then
        eval "$(zoxide init bash)"
      fi

      alias nswitch="sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos"
      alias nswitchu="sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos --upgrade"
      alias ntest="sudo /etc/nixos/scripts/nixos-rebuild-safe.sh test --flake /etc/nixos"
      alias nbuild="sudo /etc/nixos/scripts/nixos-rebuild-safe.sh build --flake /etc/nixos"
      alias ndry="sudo /etc/nixos/scripts/nixos-rebuild-safe.sh dry-activate --flake /etc/nixos"

      alias nsgc="sudo nix-store --gc"
      alias ngc="sudo nix-collect-garbage -d"
      alias ngc7="sudo nix-collect-garbage --delete-older-than 7d"
      alias ngc14="sudo nix-collect-garbage --delete-older-than 14d"
      alias ngo="sudo nix-collect-garbage --delete-old"

      alias noptimise="nix-store --optimise"
      alias nverify="nix-store --verify"
      alias nrepair="nix-store --repair"

      alias nixos="cd /etc/nixos"
      alias store="cd /nix/store"
      alias conf="cd ~/.config"

      alias nq="nix-env -qaP"
      alias nsearch="nix search nixpkgs"

      alias ll="eza -lh --group-directories-first --icons=auto"
      alias la="eza -la --group-directories-first --icons=auto"
      alias l="eza --group-directories-first --icons=auto"
      alias lt="eza --tree --level=2 --long --icons"
      alias cat="bat --paging=never"
      alias top="btop"
      alias du="dust"
      alias df="dufs"

      alias gs="git status"
      alias ga="git add"
      alias gc="git commit"
      alias gp="git push"
      alias gl="git log --oneline --graph --decorate --all"
      alias gd="git diff"
      alias gds="git diff --staged"

      alias nconf="nvim /etc/nixos/flake.nix"
      # Starship is HM-managed from this Nix source; the live
      # ~/.config/starship.toml is a symlink into the HM generation.
      # Editing the symlink directly materializes a stray file that
      # shadows HM and breaks Stylix palette control — so point sconf
      # at the source of truth instead.
      alias sconf="nvim /etc/nixos/modules/home-manager/starship.nix"
      alias bconf="nvim ~/.bashrc"

      alias sysinfo="fastfetch"
      alias neofetch="fastfetch"

      alias ..="cd .."
      alias ...="cd ../.."
      alias ....="cd ../../.."
    '';
  };

  environment.systemPackages = with pkgs; [
    bash

    zoxide

    eza
    bat
    btop
    dust
    dufs
    fastfetch
  ];
}
