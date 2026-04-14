_: {
  programs.starship = {
    enable = true;

    settings = {
      add_newline = false;

      character = {
        success_symbol = "[❯](bold cyan)";
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

      palettes = {
        zephyr = {
          green = "#50fa7b";
          cyan = "#8be9fd";
          blue = "#6272a4";
        };
        nexus = {
          blue = "#8be9fd";
          cyan = "#50fa7b";
          green = "#6272a4";
        };
        forge = {
          red = "#ff5555";
          orange = "#ffb86c";
          yellow = "#f1fa8c";
        };
        sentry = {
          yellow = "#f1fa8c";
          orange = "#ffb86c";
          red = "#ff5555";
        };
      };

      username = {
        show_always = false;
        disabled = true;
      };

      directory = {
        truncation_length = 3;
        truncation_symbol = "…/";
        repo_root_style = "bold cyan";
        repo_root_format = "[$path]($style)[$read_only]($read_only_style) ";
        read_only = " 🔒";
        style = "bold cyan";
        fish_style_pwd_rooted = "bold cyan";
      };

      git_branch = {
        format = "[$branch ]($style)";
        style = "italic cyan";
        symbol = "";
      };

      git_status = {
        format = "[$all_status]($style) ";
        style = "cyan";
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
}
