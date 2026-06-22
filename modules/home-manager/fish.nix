{pkgs, ...}: let
  theme-switch = pkgs.writeShellScriptBin "theme-switch" ''
    #!/usr/bin/env bash
    set -euo pipefail

    if [ "''${1:-}" = "list" ]; then
      find /nix/store -maxdepth 3 -path '*/base16-schemes/share/themes/*.yaml' 2>/dev/null | \
        xargs -I{} basename {} .yaml | sort -u | head -60
      exit 0
    fi

    THEME="''${1:?Usage: theme-switch <theme-name> | theme-switch list}"
    SCHEME_FILE="/etc/nixos/modules/desktop/stylix.nix"

    if ! grep -q 'share/themes/.*\.yaml' "$SCHEME_FILE"; then
      echo "ERROR: Cannot find theme line in $SCHEME_FILE"
      exit 1
    fi

    sed -i "s|share/themes/.*\.yaml|share/themes/''${THEME}.yaml|" "$SCHEME_FILE"
    echo "Theme set to $THEME. Rebuilding..."
    sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake /etc/nixos
  '';
in {
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set -gx EDITOR nvim
      set -gx VISUAL nvim

      if test -f /run/secrets/gemini-api-key
        set -gx GEMINI_API_KEY (cat /run/secrets/gemini-api-key)
      end

      if test -f /run/secrets/huggingface-token
        set -gx HF_TOKEN (cat /run/secrets/huggingface-token)
        # Ensure hf CLI token cache is populated
        if not test -f ~/.cache/huggingface/token; or test "(cat ~/.cache/huggingface/token)" != "$HF_TOKEN"
          mkdir -p ~/.cache/huggingface
          echo -n "$HF_TOKEN" > ~/.cache/huggingface/token
        end
      end

      if test -f /run/secrets/localmaxxing-api-key
        set -gx LOCALMAXXING_API_KEY (cat /run/secrets/localmaxxing-api-key)
      end

      set -gx TZ America/Winnipeg

      set -g fish_greeting


      if test -z "$FASTFETCH_DONE"
        fastfetch
        set -gx FASTFETCH_DONE 1
      end

      fish_add_path ~/.lmstudio/bin
     
      # Auto-load YubiKey SSH keys into agent - touch once per session
      if not ssh-add -l 2>/dev/null | grep -q 'j_kro-cluster'
        ssh-add -q ~/.ssh/id_ed25519_sk 2>/dev/null
      end
      if not ssh-add -l 2>/dev/null | grep -q 'j_kro@zephyr.*ED25519-SK'
        ssh-add -q ~/.ssh/id_ed25519_sk_nfc 2>/dev/null
      end

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

      alias swl "grim - | wl-copy"
      alias swlr 'grim -g (slurp) - | wl-copy'
      alias killhypr "pkill Hyprland"
      alias restartwaybar "pkill waybar && waybar &"
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

      # Container runtimes
      dgit = "lazygit";
      ddocker = "lazydocker";
      dpodman = "podman";

      # System
      s = "sudo";
      su = "systemctl user";
      ss = "systemctl --user";

      # Clipboard
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

  xdg.configFile."fastfetch/config.jsonc".text = ''
    {
      "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
      "logo": {
        "source": "nixos_small",
        "padding": {
          "top": 0,
          "right": 2
        }
      },
      "display": {
        "separator": " 󰁔 "
      },
      "modules": [
        "title",
        "separator",
        {
          "type": "os",
          "format": "{3} {12}",
          "key": "╭─ OS"
        },
        {
          "type": "kernel",
          "key": "├─󰌽 Kernel"
        },
        {
          "type": "shell",
          "format": "{1} {2}",
          "key": "├─ Shell"
        },
        {
          "type": "terminal",
          "key": "├─ Terminal"
        },
        {
          "type": "wm",
          "key": "├─ WM"
        },
        {
          "type": "cpu",
          "format": "{1} ({5})",
          "key": "├─󰻠 CPU"
        },
        {
          "type": "gpu",
          "format": "{2}",
          "key": "├─󰢮 GPU"
        },
        {
          "type": "memory",
          "format": "{1} / {2}",
          "key": "╰─󰍛 Memory"
        },
        "break",
        {
          "type": "colors",
          "symbol": "circle"
        }
      ]
    }
  '';

  home.packages = with pkgs; [
    theme-switch
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

    starship

    jq
    screen
    sshpass
  ];
}