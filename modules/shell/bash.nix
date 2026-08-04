# Bash Shell Configuration Module
# Enhanced bash with Starship prompt and productivity features
{pkgs, ...}: {
  # Enable Bash for users who prefer it (Fish is default)
  programs.bash = {
    enable = true;

    # Prompt customization
    # NOTE: guarded against one-shot command shells (bash -c / -lic wrappers).
    # Bash 5.3p15 (shipped by nixpkgs, unfixed upstream) has a heap-corruption
    # segfault in bind_tempenv_variable's temp-env array path (bug-bash
    # 2025-08 msg00070), triggered when a fresh `bash -lic` sources this rc
    # (e.g. background process wrappers). Real interactive terminals never
    # carry the -c flag in `$-`, so gating on it preserves full behavior while
    # neutralizing the crash. A real fix requires a patched bash source build.
    promptInit = ''
      case $- in
        *c*) ;;  # one-shot command shell — skip init, just run the command
        *)
          # Initialize Starship prompt for Bash
          if [ -f "${pkgs.starship}/bin/starship" ]; then
            eval "$(${pkgs.starship}/bin/starship init bash)"
          fi
          ;;
      esac
    '';

    # Interactive shell configuration
    interactiveShellInit = ''
      case $- in
        *c*) ;;  # one-shot command shell — skip init (see promptInit note)
        *)
      # Set environment variables
      export EDITOR=nvim
      export VISUAL=nvim
      export TZ=America/Winnipeg  # User timezone (system time remains UTC)

      # Better history
      export HISTSIZE=100000
      export HISTFILESIZE=100000
      export HISTCONTROL=ignoreboth:erasedups
      shopt -s histappend

      # Improved cd
      shopt -s autocd
      shopt -s cdspell
      shopt -s dirspell

      # Check window size after each command
      shopt -s checkwinsize

      # Initialize zoxide (smart cd)
      if command -v zoxide &>/dev/null; then
        eval "$(zoxide init bash)"
      fi

      # NixOS management aliases
      alias nswitch="sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos"
      alias nswitchu="sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos --upgrade"
      alias ntest="sudo /etc/nixos/scripts/nixos-rebuild-safe.sh test --flake /etc/nixos"
      alias nbuild="sudo /etc/nixos/scripts/nixos-rebuild-safe.sh build --flake /etc/nixos"
      alias ndry="sudo /etc/nixos/scripts/nixos-rebuild-safe.sh dry-activate --flake /etc/nixos"

      # Garbage collection
      alias nsgc="sudo nix-store --gc"
      alias ngc="sudo nix-collect-garbage -d"
      alias ngc7="sudo nix-collect-garbage --delete-older-than 7d"
      alias ngc14="sudo nix-collect-garbage --delete-older-than 14d"
      alias ngo="sudo nix-collect-garbage --delete-old"

      # Optimization
      alias noptimise="nix-store --optimise"
      alias nverify="nix-store --verify"
      alias nrepair="nix-store --repair"

      # NixOS navigation
      alias nixos="cd /etc/nixos"
      alias store="cd /nix/store"
      alias conf="cd ~/.config"

      # Package management
      alias nq="nix-env -qaP"
      alias nsearch="nix search nixpkgs"

      # Common aliases
      alias ll="eza -lh --group-directories-first --icons=auto"
      alias la="eza -la --group-directories-first --icons=auto"
      alias l="eza --group-directories-first --icons=auto"
      alias lt="eza --tree --level=2 --long --icons"
      alias cat="bat --paging=never"
      alias top="btop"
      alias du="dust"
      alias df="dufs"

      # Git shortcuts
      alias gs="git status"
      alias ga="git add"
      alias gc="git commit"
      alias gp="git push"
      alias gl="git log --oneline --graph --decorate --all"
      alias gd="git diff"
      alias gds="git diff --staged"

      # Quick config editing
      alias nconf="nvim /etc/nixos/flake.nix"
      # starship config is HM/stylix-managed (modules/home-manager/starship.nix);
      # editing the live ~/.config/starship.toml shadows the managed symlink and
      # re-triggers the "Could not find color palette: noctalia" WARN. Point sconf
      # at the SOURCE OF TRUTH so edits go through the NixOS module + switch.
      alias sconf="nvim /etc/nixos/modules/home-manager/starship.nix"
      alias bconf="nvim ~/.bashrc"

      # System information
      alias sysinfo="fastfetch"
      alias neofetch="fastfetch"

      # Navigation
      alias ..="cd .."
      alias ...="cd ../.."
      alias ....="cd ../../.."
    '';
  };

  # Install required packages for Bash
  environment.systemPackages = with pkgs; [
    # Shell tools
    bash

    # Navigation
    zoxide

    # Enhanced tools (shared with Fish)
    eza
    bat
    btop
    dust
    dufs
    fastfetch
  ];
}
