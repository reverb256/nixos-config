{config, ...}: let
  c = config.lib.stylix.colors.withHashtag;
in {
  programs.starship = {
    enable = true;

    settings = {
      add_newline = false;

      character = {
        success_symbol = "[❯](bold ${ c.base0D})";
        error_symbol = "[✗](bold ${ c.base08})";
        vicmd_symbol = "[❮](bold ${ c.base0B})";
      };

      format = "$hostname$git_branch$git_status$nix_shell$character";

      command_timeout = 10000;

      hostname = {
        ssh_only = false;
        format = "[$hostname]($style) ";
        style = "bold ${ c.base0B}";
        disabled = false;
      };

      username = {
        show_always = false;
        disabled = true;
      };

      directory = {
        truncation_length = 3;
        truncation_symbol = "…/";
        repo_root_style = "bold ${ c.base0D}";
        repo_root_format = "[$path]($style)[$read_only]($read_only_style) ";
        read_only = " 🔒";
        style = "bold ${ c.base0D}";
        fish_style_pwd_rooted = "bold ${ c.base0D}";
      };

      git_branch = {
        format = "[$branch ]($style)";
        style = "italic ${ c.base0D}";
        symbol = "";
      };

      git_status = {
        format = "[$all_status]($style) ";
        style = "${ c.base0D}";
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
