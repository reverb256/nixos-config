# Zsh Shell Configuration Module
# Sole interactive + login shell for j_kro (POSIX) so AI agents, `sh -c`, and
# SSH sessions get predictable bash-compatible behavior. Fish was removed
# 2026-08-18 (see issue #645 — login shell was already zsh).
{ pkgs, ... }: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;

    # History settings (shared across interactive zsh sessions)
    histSize = 100000;
    histFile = "$HOME/.zsh_history";

    setOptions = [
      "AUTO_CD"
      "CD_SILENT"
      "INC_APPEND_HISTORY"
      "HIST_IGNORE_ALL_DUPS"
      "SHARE_HISTORY"
    ];

    # Interactive shell configuration (prompt, navigation, environment)
    # NOTE: starship init is NOT here — Layer-2 home-manager owns it via
    # programs.starship.enableZshIntegration (home-manager-config/modules/starship.nix).
    # Layer-1 keeps zsh's own prompt defaults; HM injects starship into
    # ~/.config/zsh/.zshrc. Single owner = no double init.
    interactiveShellInit = '''
      # Environment
      export EDITOR=nvim
      export VISUAL=nvim
      export TZ=America/Winnipeg  # User timezone (system time remains UTC)

      # zoxide (smart cd)
      if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init zsh)"
      fi

      # fzf (history + completion integration)
      if command -v fzf >/dev/null 2>&1; then
        source <(fzf --zsh)
      fi
    '';

    # Shell aliases (mirror modules/shell/bash.nix)
    shellAliases = {
      # NixOS management
      nswitch = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos";
      nswitchu = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos --upgrade";
      ntest = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh test --flake /etc/nixos";
      nbuild = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh build --flake /etc/nixos";
      ndry = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh dry-activate --flake /etc/nixos";

      # Garbage collection
      nsgc = "sudo nix-store --gc";
      ngc = "sudo nix-collect-garbage -d";
      ngc7 = "sudo nix-collect-garbage --delete-older-than 7d";
      ngc14 = "sudo nix-collect-garbage --delete-older-than 14d";
      ngo = "sudo nix-collect-garbage --delete-old";

      # Optimization
      noptimise = "nix-store --optimise";
      nverify = "nix-store --verify";
      nrepair = "nix-store --repair";

      # NixOS navigation
      nixos = "cd /etc/nixos";
      store = "cd /nix/store";
      conf = "cd ~/.config";

      # Package management
      nq = "nix-env -qaP";
      nsearch = "nix search nixpkgs";

      # Common aliases
      ll = "eza -lh --group-directories-first --icons=auto";
      la = "eza -la --group-directories-first --icons=auto";
      l = "eza --group-directories-first --icons=auto";
      lt = "eza --tree --level=2 --long --icons";
      cat = "bat --paging=never";
      top = "btop";
      du = "dust";
      df = "dufs";

      # Git shortcuts
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline --graph --decorate --all";
      gd = "git diff";
      gds = "git diff --staged";

      # System information
      sysinfo = "fastfetch";
      neofetch = "fastfetch";

      # Navigation
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";

      # ScopeBuddy (gaming helpers)
      scb = "scopebuddy";
      scopebuddy = "scopebuddy";
      scb-detect = "scopebuddy-detect";
      scb-launch = "scopebuddy-launch";
    };
  };

  # Install required packages (shared across shells)
  environment.systemPackages = with pkgs; [
    zsh

    # Navigation
    zoxide
    fzf

    # Enhanced tools
    eza
    bat
    btop
    dust
    dufs
    fastfetch
    starship

    # Container / Docker-compose helpers
    lazydocker
    podman-compose
  ];
}
