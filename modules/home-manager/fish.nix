# Home Manager Fish Shell Configuration
# Centralized Fish configuration for j_kro across all cluster nodes
# This replaces local ~/.config/fish/config.fish files
{pkgs, ...}: {
  programs.fish = {
    enable = true;

    # Interactive shell configuration
    interactiveShellInit = ''
      # ============================================================================
      # ENVIRONMENT VARIABLES
      # ============================================================================
      set -gx EDITOR nvim
      set -gx VISUAL nvim

      # Disable fish greeting
      set -g fish_greeting

      # ============================================================================
      # PATH EXTENSIONS
      # ============================================================================
      # LM Studio CLI
      fish_add_path ~/.lmstudio/bin

      # Local bin directory
      fish_add_path ~/.local/bin

      # ============================================================================
      # INITIALIZATION
      # ============================================================================
      # Initialize zoxide (smart cd)
      zoxide init fish | source

      # Initialize starship prompt
      starship init fish | source

      # ============================================================================
      # NIXOS MANAGEMENT ALIASES
      # ============================================================================
      # Note: These use nixos-rebuild-safe.sh which automatically pauses mining
      # during builds to maximize performance, then resumes mining afterward.

      # System rebuild commands (with automatic mining pause)
      alias nswitch "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos"
      alias nswitchu "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos --upgrade"
      alias ntest "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh test --flake /etc/nixos"
      alias nbuild "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh build --flake /etc/nixos"
      alias ndry "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh dry-activate --flake /etc/nixos"

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

      # ============================================================================
      # DEVELOPMENT TOOLS
      # ============================================================================
      alias g lgit          # Lazy git
      alias g ldocker       # Lazy docker (when using Docker)
      alias g lpodman       # Lazy podman

      # ============================================================================
      # COMMON ALIASES
      # ============================================================================
      alias ll "eza -lh --group-directories-first --icons=auto"
      alias la "eza -la --group-directories-first --icons=auto"
      alias l "eza --group-directories-first --icons=auto"
      alias lt "eza --tree --level=2 --long --icons"
      alias cat "bat --paging=never"
      alias top "btop"
      alias du "dust"
      alias df "dufs"

      # ============================================================================
      # GIT SHORTCUTS
      # ============================================================================
      alias gs "git status"
      alias ga "git add"
      alias gc "git commit"
      alias gp "git push"
      alias gl "git log --oneline --graph --decorate --all"
      alias gd "git diff"
      alias gds "git diff --staged"

      # ============================================================================
      # QUICK CONFIG EDITING
      # ============================================================================
      alias nconf "nvim /etc/nixos/flake.nix"
      alias hconf "nvim ~/.config/hypr/hyprland.conf"
      alias fconf "nvim ~/.config/fish/config.fish"
      alias sconf "nvim ~/.config/starship.toml"

      # ============================================================================
      # SYSTEM INFORMATION
      # ============================================================================
      alias sysinfo "fastfetch"
      alias neofetch "fastfetch"

      # ============================================================================
      # AUDIO PROFILE SWITCHING (Zephyr-specific)
      # ============================================================================
      alias audio-pc="/etc/nixos/docs/audio-profiles.sh pc"
      alias audio-tv="/etc/nixos/docs/audio-profiles.sh tv"
      alias audio-both="/etc/nixos/docs/audio-profiles.sh pc+tv"
      alias audio-status="/etc/nixos/docs/audio-profiles.sh status"

      # ============================================================================
      # CLIPBOARD (Wayland)
      # ============================================================================
      alias wclip "wl-copy"
      alias wpaste "wl-paste"

      # ============================================================================
      # SCREENSHOTS (Wayland)
      # ============================================================================
      alias swl "grim - | wl-copy"                      # Wayland screenshot
      alias swlr "grim -g \\"\$(slurp)\" - | wl-copy"       # Region screenshot

      # ============================================================================
      # PROCESS MANAGEMENT (Wayland)
      # ============================================================================
      alias killhypr "pkill Hyprland"
      alias restartwaybar "pkill waybar && waybar &"

      # ============================================================================
      # NAVIGATION
      # ============================================================================
      alias .. "cd .."
      alias ... "cd ../.."
      alias .... "cd ../../.."
    '';

    # Abbreviations (shellAbbrs)
    shellAbbrs = {
      # NixOS abbreviations
      nrb = "nixos-rebuild";
      ns = "nix-shell";
      nfp = "nix flake show";

      # Development abbreviations
      gs = "git status";
      gc = "git commit";
      gp = "git push";

      # System abbreviations
      s = "sudo";
      su = "systemctl user";
      ss = "systemctl --user";
    };

    # Functions
    functions = {
      # Quick grep with ripgrep
      rg = {
        description = "Search with ripgrep";
        body = ''
          command ripgrep --color=always $argv
        '';
      };

      # Quick find with fd
      fd = {
        description = "Find files with fd";
        body = ''
          command fd --color=always $argv
        '';
      };
    };

    # Plugins
    plugins = [
      {
        name = "z";
        src = pkgs.fishPlugins.z;
      }
      {
        name = "fzf";
        src = pkgs.fishPlugins.fzf;
      }
      {
        name = "fzf-fish";
        src = pkgs.fishPlugins.fzf-fish;
      }
    ];
  };

  # Install required packages
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
  ];

  # Starship prompt configuration
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[❯](bold cyan)";
        error_symbol = "[✗](bold red)";
        vicmd_symbol = "[❮](bold green)";
      };
      format = "$hostname$username$directory$git_branch$git_status$kubernetes$character";
      command_timeout = 10000;

      hostname = {
        ssh_only = false;
        ssh_symbol = "🌐 ";
        format = "[$hostname]($style) ";
        style = "bold dimmed green";
        disabled = false;
      };

      username = {
        show_always = false;
        format = "[$user]($style) ";
        style_user = "bold yellow";
        disabled = false;
      };

      directory = {
        truncation_length = 3;
        truncation_symbol = "…/";
        repo_root_style = "bold cyan";
        repo_root_format = "[$path]($style)[$read_only]($read_only_style) ";
        read_only = " 🔒";
        style = "bold cyan";
        truncation_symbol = "…/";
      };

      git_branch = {
        format = "[$branch]($style) ";
        style = "italic cyan";
        symbol = " ";
      };

      git_status = {
        format = "[$all_status]($style) ";
        style = "cyan";
        ahead = "⇡ ";
        behind = "⇣ ";
        diverged = "⇕ ";
        conflicted = "✖";
        untracked = "•";
        modified = "▲";
        staged = "●";
        stashed = "≡";
      };

      kubernetes = {
        symbol = "☸ ";
        format = "[$context]($style) ";
        style = "bold blue";
        disabled = false;
      };

      nix_shell = {
        symbol = "❄️ ";
        format = "[$state]($style) ";
        style = "bold purple";
        disabled = false;
        heuristic = true;
      };

      docker_context = {
        symbol = "🐳 ";
        format = "[$context]($style) ";
        style = "bold blue";
        disabled = false;
      };

      nodejs = {
        symbol = "⬢ ";
        format = "[$version]($style) ";
        style = "bold green";
        disabled = false;
      };

      # Disable unused modules
      sudo.disabled = true;
      python.disabled = true;
      ruby.disabled = true;
      golang.disabled = true;
      rust.disabled = true;
      terraform.disabled = true;
      vagrant.disabled = true;
      conda.disabled = true;
      meson.disabled = true;
      spack.disabled = true;
    };
  };
}
