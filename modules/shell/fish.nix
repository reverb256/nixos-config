# Fish Shell Configuration Module
# Enhanced shell with NixOS management aliases and productivity functions
{pkgs, ...}: {
  # Enable Fish shell
  programs.fish = {
    enable = true;

    # Interactive shell configuration
    interactiveShellInit = ''
      # Set environment variables
      set -gx EDITOR nvim
      set -gx VISUAL nvim

      # Disable fish greeting
      set -g fish_greeting

      # Initialize zoxide (smart cd)
      zoxide init fish | source

      # Initialize starship prompt
      starship init fish | source

      # NixOS management aliases
      # ====================================

      # System rebuild commands
      alias nswitch "sudo nixos-rebuild switch --flake /etc/nixos"
      alias nswitchu "sudo nixos-rebuild switch --flake /etc/nixos --upgrade"
      alias ntest "sudo nixos-rebuild test --flake /etc/nixos"
      alias nbuild "sudo nixos-rebuild build --flake /etc/nixos"
      alias ndry "sudo nixos-rebuild dry-activate --flake /etc/nixos"

      # Garbage collection
      alias nsgc "sudo nix-store --gc"
      alias ngc "sudo nix-collect-garbage -d"
      alias ngc7 "sudo nix-collect-garbage --delete-older-than 7d"
      alias ngc14 "sudo nix-collect-garbage --delete-older-than 14d"
      alias ngo "sudo nix-collect-garbage --delete-old"

      # Optimization
      alias noptimise "nix-store --optimise"
      alias nverify "nix-store --verify"
      alias nrepair "nix-store --repair"

      # NixOS navigation
      alias nixos "cd /etc/nixos"
      alias store "cd /nix/store"
      alias conf "cd ~/.config"

      # Package management
      alias nq "nix-env -qaP"
      alias nsearch "nix search nixpkgs"

      # Development tools
      alias g lgit          # Lazy git
      alias g ldocker       # Lazy docker (when using Docker)
      alias g lpodman       # Lazy podman

      # Common aliases
      alias ll "eza -lh --group-directories-first --icons=auto"
      alias la "eza -la --group-directories-first --icons=auto"
      alias l "eza --group-directories-first --icons=auto"
      alias lt "eza --tree --level=2 --long --icons"
      alias cat "bat --paging=never"
      alias top "btop"
      alias du "dust"
      alias df "dufs"

      # Git shortcuts
      alias gs "git status"
      alias ga "git add"
      alias gc "git commit"
      alias gp "git push"
      alias gl "git log --oneline --graph --decorate --all"
      alias gd "git diff"
      alias gds "git diff --staged"

      # Quick config editing
      alias nconf "nvim /etc/nixos/flake.nix"
      alias hconf "nvim ~/.config/hypr/hyprland.conf"
      alias fconf "nvim ~/.config/fish/config.fish"
      alias sconf "nvim ~/.config/starship.toml"

      # System information
      alias sysinfo "fastfetch"
      alias neofetch "fastfetch"

      # Clipboard (Wayland)
      alias wclip "wl-copy"
      alias wpaste "wl-paste"

      # Screenshots
      alias swl "grim - | wl-copy"                      # Wayland screenshot
      alias swlr "grim -g \"\$(slurp)\" - | wl-copy"       # Region screenshot

      # Process management
      alias killhypr "pkill Hyprland"
      alias restartwaybar "pkill waybar && waybar &"

      # Navigation
      alias .. "cd .."
      alias ... "cd ../.."
      alias .... "cd ../../.."
    '';

    # Abbreviations (shellAbbrs)
    shellAbbrs = {
      # NixOS abbreviations
      nrb = "nixos-rebuild";
      ns = "nswitch";

      # Git abbreviations
      co = "checkout";
      cm = "commit";
      br = "branch";
      st = "status";

      # Common typos
      gerp = "grep";
      gti = "git";
    };
  };

  # Install required packages
  environment.systemPackages = with pkgs; [
    # Shell
    fish
    fishPlugins.foreign-env
    fishPlugins.fzf-fish

    # Prompt
    starship

    # Navigation
    zoxide

    # Enhanced tools
    eza # Better ls
    bat # Better cat
    btop # Better top
    dust # Better du
    dufs # Better df
    fastfetch # System info

    # Git tools
    lazygit

    # Clipboard
    wl-clipboard

    # Screenshots
    grim
    slurp

    # Fuzzy finder
    fzf

    # Podman management (when needed)
    lazydocker
    podman-compose
  ];

  # Fish plugins are loaded from systemPackages
  # No additional configuration needed
}
