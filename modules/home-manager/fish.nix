{pkgs, ...}: {
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set -gx EDITOR nvim
      set -gx VISUAL nvim

      if test -f /run/agenix/gemini-api-key
        set -gx GEMINI_API_KEY (cat /run/agenix/gemini-api-key)
      end

      set -gx TZ America/Winnipeg

      set -g fish_greeting

      fish_add_path ~/.lmstudio/bin

      fish_add_path ~/.local/bin

      zoxide init fish | source



      alias nswitch "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos"
      alias nswitchu "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos --upgrade"
      alias ntest "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh test --flake /etc/nixos"
      alias nbuild "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh build --flake /etc/nixos"
      alias ndry "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh dry-activate --flake /etc/nixos"

      alias nsgc "sudo nix-store --gc"
      alias ngc "sudo nix-collect-garbage -d"
      alias ngc7 "sudo nix-collect-garbage --delete-older-than 7d"
      alias ngc14 "sudo nix-collect-garbage --delete-older-than 14d"
      alias ngo "sudo nix-collect-garbage --delete-old"

      alias noptimise "nix-store --optimise"
      alias nverify "nix-store --verify"
      alias nrepair "nix-store --repair"

      alias nixos "cd /etc/nixos"
      alias store "cd /nix/store"
      alias conf "cd ~/.config"

      alias nq "nix-env -qaP"
      alias nsearch "nix search nixpkgs"

      alias g lgit
      alias g ldocker
      alias g lpodman

      alias ll "eza -lh --group-directories-first --icons=auto"
      alias la "eza -la --group-directories-first --icons=auto"
      alias l "eza --group-directories-first --icons=auto"
      alias lt "eza --tree --level=2 --long --icons"
      alias cat "bat --paging=never"
      alias top "btop"
      alias du "dust"
      alias df "dufs"

      alias gs "git status"
      alias ga "git add"
      alias gc "git commit"
      alias gp "git push"
      alias gl "git log --oneline --graph --decorate --all"
      alias gd "git diff"
      alias gds "git diff --staged"

      alias nconf "nvim /etc/nixos/flake.nix"
      alias fconf "nvim ~/.config/fish/config.fish"

      alias sysinfo "fastfetch"
      alias neofetch "fastfetch"

      alias .. "cd .."
      alias ... "cd ../.."
      alias .... "cd ../../.."

      alias swl "grim - | wl-copy"
      alias swlr 'grim -g (slurp) - | wl-copy'

      alias killhypr "pkill Hyprland"
      alias restartwaybar "pkill waybar && waybar &"
    '';

    shellAbbrs = {
      nrb = "nixos-rebuild";
      ns = "nix-shell";
      nfp = "nix flake show";

      gs = "git status";
      gc = "git commit";
      gp = "git push";

      s = "sudo";
      su = "systemctl user";
      ss = "systemctl --user";

      wclip = "wl-copy";
      wpaste = "wl-paste";
    };

    functions = {
      rg = {
        description = "Search with ripgrep";
        body = ''
          command ripgrep --color=always $argv
        '';
      };

      fd = {
        description = "Find files with fd";
        body = ''
          command fd --color=always $argv
        '';
      };

      grim-region = {
        description = "Capture region to file";
        body = ''
          grim -g (slurp) $argv
        '';
      };
    };
  };

  home.packages = with pkgs; [
    eza
    bat
    btop
    dust
    dufs
    fastfetch
    zoxide
    ripgrep
    fd
    fzf
    lazygit

    starship

    jq
    screen
    sshpass
    tmux
    gh
  ];
}
