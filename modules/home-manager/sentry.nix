# Sentry Home-Manager Configuration
# Monitoring, logging + full shell and theming configuration

{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkMerge;
in {
  home-manager.users.j_kro = { pkgs, ... }: {
    home.stateVersion = "26.05";

    # Shell configuration (fish with starship)
    programs.fish = {
      enable = true;

      interactiveShellInit = ''
        set -gx EDITOR nvim
        set -gx VISUAL nvim

        if test -f /run/agenix/gemini-api-key
          set -gx GEMINI_API_KEY (cat /run/agenix/gemini-api-key)
        end

        if test -f /run/agenix/huggingface-token
          set -gx HF_TOKEN (cat /run/agenix/huggingface-token)
          if not test -f ~/.cache/huggingface/token; or test (cat ~/.cache/huggingface/token) != "$HF_TOKEN"
            mkdir -p ~/.cache/huggingface
            echo -n "$HF_TOKEN" > ~/.cache/huggingface/token
          end
        end

        if test -f /run/agenix/localmaxxing-api-key
          set -gx LOCALMAXXING_API_KEY (cat /run/agenix/localmaxxing-api-key)
        end

        set -gx TZ America/Winnipeg
        set -g fish_greeting

        if test -z "$FASTFETCH_DONE"
          fastfetch
          set -gx FASTFETCH_DONE 1
        end

        fish_add_path ~/.lmstudio/bin
        fish_add_path ~/.local/bin

        zoxide init fish | source
        fzf --fish | source

        alias ll "eza -lh --group-directories-first --icons=auto"
        alias la "eza -la --group-directories-first --icons=auto"
        alias l "eza --group-directories-first --icons=auto"
        alias lt "eza --tree --level=2 --long --icons"
        alias cat "bat --paging=never"
        alias top "btop"
        alias du "dust"
        alias df "dufs"
      '';

      shellAbbrs = {
        # Git
        gs = "git status";
        ga = "git add";
        gc = "git commit";
        gp = "git push";
        gl = "git log --oneline --graph --decorate --all";
        gd = "git diff";
        gds = "git diff --staged";

        # NixOS
        nswitch = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos";
        nswitchu = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos --upgrade";
        ntest = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh test --flake /etc/nixos";
        nbuild = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh build --flake /etc/nixos";
        ndry = "sudo /etc/nixos/scripts/nixos-rebuild-safe.sh dry-activate --flake /etc/nixos";
        nconf = "nvim /etc/nixos/flake.nix";
        fconf = "nvim ~/.config/fish/config.fish";

        nsgc = "sudo nix-store --gc";
        ngc = "sudo nix-collect-garbage -d";
        ngc7 = "sudo nix-collect-garbage --delete-older-than 7d";
        ngc14 = "sudo nix-collect-garbage --delete-older-than 14d";
        ngo = "sudo nix-collect-garbage --delete-old";
        noptimise = "nix-store --optimise";
        nverify = "nix-store --verify";
        nrepair = "nix-store --repair";

        nixos = "cd /etc/nixos";
        store = "cd /nix/store";
        conf = "cd ~/.config";
        nq = "nix-env -qaP";
        nsearch = "nix search nixpkgs";
        nrb = "nixos-rebuild";
        ns = "nix-shell";
        nfp = "nix flake show";

        # Navigation
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";

        # Quick commands
        sysinfo = "fastfetch";
        neofetch = "fastfetch";

        # System
        s = "sudo";
        su = "systemctl user";
        ss = "systemctl --user";
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
      };
    };

    # Starship prompt (with stylix colors)
    programs.starship = mkIf (config.stylix.enable or false) {
      enable = true;

      settings = {
        add_newline = false;

        character = {
          success_symbol = "[❯](bold blue)";
          error_symbol = "[✗](bold red)";
          vicmd_symbol = "[❮](bold green)";
        };

        format = "$hostname$git_branch$git_status$nix_shell$character";

        command_timeout = 10000;

        hostname = {
          ssh_only = false;
          format = "[$hostname]($style) ";
          style = "bold green";
          disabled = false;
        };

        username = {
          show_always = false;
          disabled = true;
        };

        directory = {
          truncation_length = 3;
          truncation_symbol = "…/";
          repo_root_style = "bold blue";
          repo_root_format = "[$path]($style)[$read_only]($read_only_style) ";
          read_only = " 🔒";
          style = "bold blue";
          fish_style_pwd_rooted = "bold blue";
        };

        git_branch = {
          format = "[$branch ]($style)";
          style = "italic blue";
          symbol = "";
        };

        git_status = {
          format = "[$all_status]($style) ";
          style = "blue";
          ahead = "⇡";
          behind = "⇣";
          diverged = "⇕";
          conflicted = "✖";
          untracked = "•";
          modified = "▲";
          staged = "●";
          stashed = "≡";
        };

        nix_shell = {
          symbol = "";
          format = "[local ]($style)";
          style = "bold dimmed white";
          disabled = false;
          heuristic = true;
        };

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
        kubernetes.disabled = true;
        docker_context.disabled = true;
        nodejs.disabled = true;
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

    # SSH configuration
    programs.ssh = {
      enable = true;
      extraConfig = ''
        Host 10.1.1.*
          StrictHostKeyChecking no
          UserKnownHostsFile ~/.ssh/known_hosts
      '';
    };

    # GPG configuration
    programs.gpg.enable = true;

    # Terminal tools
    home.packages = with pkgs; [
      # Terminal
      alacritty

      # Shell utilities
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

      # Monitoring
      glances

      # Log analysis
      gron
      jq

      # Network tools
      tcpdump
      wireshark-cli

      # System tools
      jq
      screen
      sshpass
    ];

    # Common .config entries
    xdg.configFile."alacritty/alacritty.yml".source = ../../modules/home-manager/alacritty.yml;

    # Files in home directory
    home.file.".screenrc".source = ../../modules/home-manager/dotfiles/.screenrc;
    home.file.".gtkrc-2.0".source = ../../modules/home-manager/dotfiles/.gtkrc-2.0;

    # CRITICAL: Zen Browser NOT managed here - see preservation.nix
    # Backup: /data/backups/sentry-20260531/zen-browser-profile.tar.gz (1.3 GB)
  };
}