# Working Home Manager Example for Fish Shell + Starship Prompt
#
# This example shows how to configure Fish shell and Starship
# using Home Manager, which is often preferred for user-specific
# shell configurations.
{pkgs, ...}: {
  config = {
    # ================================
    # Home Manager Fish Configuration
    # ================================
    programs.fish = {
      enable = true;
      enableCompletion = true;
      enableEraseToWordBoundaries = true;

      # Shell aliases
      shellAliases = {
        ll = "ls -la --color=auto";
        la = "ls -la --color=auto";
        l = "ls --color=auto";
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";

        # Git aliases
        gs = "git status";
        ga = "git add";
        gc = "git commit";
        gp = "git push";
        gl = "git log --oneline";
        gd = "git diff";
        gco = "git checkout";

        # System aliases
        grep = "grep --color=auto";
        rg = "rg --color=auto";
        ps = "ps aux";
        df = "df -h";
        du = "du -h";

        # Home Manager rebuild aliases
        hm-update = "home-manager switch";
        hm-build = "home-manager build";
        hm-test = "home-manager test";
      };

      # Interactive shell initialization
      interactiveShellInit = ''
        # Environment variables
        set -gx EDITOR nvim
        set -gx VISUAL nvim
        set -gx BROWSER firefox
        set -gx TERMINAL konsole
        set -gx PAGER less
        set -gx LESS "-R --mouse --wheel-lines=3"

        # Add user bin to PATH
        set -Ua fish_user_paths "$HOME/.local/bin"

        # Fast startup optimizations
        set -gx FISH_NO_UNICODE_BREAK 1
        set -gx FISH_NO_OLD_KEY_BINDINGS 1

        # History settings
        set -U fish_history_limit 10000

        # Color settings (optimized for readability)
        set -x fish_color_autosuggestion brblack
        set -x fish_color_cancel -r
        set -x fish_color_command normal
        set -x fish_color_comment red
        set -x fish_color_cwd green
        set -x fish_color_cwd_root red
        set -x fish_color_end green
        set -x fish_color_error brred
        set -x fish_color_escape brcyan
        set -x fish_color_history_current --bold
        set -x fish_color_host normal
        set -x fish_color_host_remote yellow
        set -x fish_color_normal normal
        set -x fish_color_operator brcyan
        set -x fish_color_param cyan
        set -x fish_color_quote yellow
        set -x fish_color_redirection cyan --bold
        set -x fish_color_search_match white --background=brblack --bold
        set -x fish_color_selection white --background=brblack --bold
        set -x fish_color_status red
        set -x fish_color_user brgreen
        set -x fish_color_valid_path --underline
        set -x fish_key_bindings fish_default_key_bindings

        # Pager colors
        set -x fish_pager_color_background ""
        set -x fish_pager_color_completion normal
        set -x fish_pager_color_description yellow --italic
        set -x fish_pager_color_prefix normal --bold --underline
        set -x fish_pager_color_progress brwhite --background=cyan --bold
        set -x fish_pager_color_selected_background -r
      '';

      # Login shell initialization
      loginShellInit = ''
        # Source any existing shell configuration files
        if test -f ~/.config/fish/conf.d/*.fish
          for file in ~/.config/fish/conf.d/*.fish
            source $file
          end
        end
      '';
    };

    # ================================
    # Home Manager Starship Configuration
    # ================================
    programs.starship = {
      enable = true;
      enableFishIntegration = true;
      settings = {
        # Basic formatting
        format = "$all";
        scan_timeout = 10;
        add_newline = false;

        # Performance: Disable slow modules by default
        disabled = [
          "aws"
          "gcloud"
          "openstack"
          "kubernetes"
          "docker"
          "docker_context"
        ];

        # Git status (optimized for speed)
        git_status = {
          scan_timeout = 5;
          ahead = "⇡${count}";
          behind = "⇣${count}";
          diverged = "⇕${count}";
          conflicted = "✖";
          untracked = "•";
          stashed = "⚑";
          modified = "▲";
          staged = "●";
          renamed = "»";
          deleted = "✗";
        };

        # Git branch
        git_branch = {
          symbol = "🌿 ";
          truncation_length = 20;
          truncation_symbol = "…/";
        };

        # Directory (performance optimized)
        directory = {
          truncation_length = 3;
          truncation_symbol = "…/";
          truncate_to_repo = true;
        };

        # Command duration (only show for long commands)
        cmd_duration = {
          min_time = 500;
          format = "took [${duration}](${style})";
        };

        # Node.js
        nodejs = {
          symbol = "📦 ";
          format = "via [${symbol}${version}](${style})";
        };

        # Python
        python = {
          symbol = "🐍 ";
          format = "via [${symbol}${version}](${style})";
        };

        # Rust
        rust = {
          symbol = "🦀 ";
          format = "via [${symbol}${version}](${style})";
        };

        # Go
        golang = {
          symbol = "🐹 ";
          format = "via [${symbol}${version}](${style})";
        };

        # Username (only show when not current user)
        username = {
          show_always = false;
          format = "[${user}](${style})@";
          ignore_case = true;
        };

        # Hostname
        hostname = {
          format = "[${hostname}](${style})";
        };

        # Battery (if available)
        battery = {
          full_symbol = "🔋";
          charging_symbol = "⚡️";
          discharging_symbol = "💀";
          unknown_symbol = "❓";
          empty_symbol = "🪫";
        };

        # Time
        time = {
          format = "🕙[${time}](${style})";
          time_format = "%H:%M:%S";
          utc_time_offset = "local";
        };

        # Kubernetes (only if context is set)
        kubernetes = {
          disabled = false;
          format = "on [⛵ ${context}](${style}) in [${namespace}](${style}) ";
        };

        # Docker Context (only if available)
        docker_context = {
          format = "via [🐋 ${context}](${style})";
        };

        # Package (npm, cargo, etc.)
        package = {
          format = "is [📦 ${version}](${style})";
        };

        # Shell (show when using non-standard shells)
        shell = {
          format = "on [${symbol}${version}](${style})";
        };

        # Status (only show on error)
        status = {
          format = "[${symbol}${status}](${style})";
          pipestatus_format = "[${symbol}${common_meaning}(${pipestatus})](${style})";
        };

        # Jobs (background processes)
        jobs = {
          format = "[${symbol}${number}](${style})";
        };
      };
    };

    # ================================
    # Alternative: Minimal Configuration
    # ================================
    programs.starship-minimal = {
      enable = false; # Set to true to use this instead
      enableFishIntegration = true;
      settings = {
        # Minimal prompt with just git status and directory
        format = "$git_status$directory$cmd_duration$line_break$character";

        # Git status with custom symbols
        git_status = {
          ahead = "↑${count}";
          behind = "↓${count}";
          diverged = "↕${count}";
          conflicted = "✗";
          untracked = "•";
          stashed = "⚑";
          modified = "▲";
          staged = "●";
          renamed = "»";
          deleted = "✗";
        };

        # Directory with short path
        directory = {
          truncation_length = 2;
          truncation_symbol = "…/";
          truncate_to_repo = false;
        };

        # Character prompt
        character = {
          success_symbol = "[➜](bold green)";
          error_symbol = "[✗](bold red)";
          vicmd_symbol = "[❮](bold blue)";
        };
      };
    };

    # ================================
    # User Shell Configuration
    # ================================
    users.users.j_kro = {
      shell = pkgs.fish;
    };

    # ================================
    # Session Variables
    # ================================
    environment.sessionVariables = {
      SHELL = "${pkgs.fish}/bin/fish";
      EDITOR = "nvim";
      VISUAL = "nvim";
      BROWSER = "firefox";
      TERMINAL = "konsole";
      PAGER = "less";
    };

    # ================================
    # Fish Functions (Optional)
    # ================================
    programs.fish.functions = {
      # Custom function to show current working directory
      cwd = {
        body = "echo (pwd)";
        description = "Show current working directory";
      };

      # Custom function to show git status
      git-status = {
        body = "git status --short";
        description = "Show git status in short format";
      };

      # Custom function to show system info
      sysinfo = {
        body = "uname -a; echo ''; echo 'Memory:'; free -h; echo ''; echo 'Disk:'; df -h";
        description = "Show system information";
      };
    };
  };
}
# ================================
# USAGE IN HOME MANAGER
# ================================
# To use this in your home.nix:
# {
#   imports = [ ./modules/home-manager-fish-starship.nix ];
# }
# To use this in your home-manager configuration:
# home-manager.users.j_kro = {
#   imports = [ ./modules/home-manager-fish-starship.nix ];
# };
# To enable the minimal configuration:
# home-manager.users.j_kro = {
#   imports = [ ./modules/home-manager-fish-starship.nix ];
#   programs.starship-minimal.enable = true;
#   programs.starship.enable = false;
# };
# ================================
# INTEGRATION WITH NIXOS MODULE
# ================================
# If you want to use both NixOS and Home Manager:
# 1. Keep the NixOS module for system-wide configuration
# 2. Use Home Manager for user-specific configuration
# 3. Ensure both have enableFishIntegration = true
# 4. Home Manager will override user-specific settings
# Example NixOS configuration:
# {
#   imports = [ ./modules/fish-starship.nix ]; # Basic setup
#   users.users.j_kro = {
#     isNormalUser = true;
#     home = "/home/j_kro";
#     shell = pkgs.fish;
#   };
# }
# Example Home Manager configuration:
# {
#   imports = [ ./modules/home-manager-fish-starship.nix ];
#   programs.starship.settings = {
#     # User-specific starship settings
#     format = "$all";
#   };
# }

