{
  config,
  pkgs,
  lib,
  ...
}: let
  c = config.lib.stylix.colors.withHashtag;

  minerScript = "${config.xdg.configHome}/fish/scripts/miner-status.sh";
in {
  programs.starship = {
    enable = true;

    settings = {
      # ── Three-line layout ──────────────────────────────────────
      format = ''
        $time$hostname
        $directory$git_branch$git_status$nix_shell$custom.miner$fill$cmd_duration
        $character'';

      add_newline = false;
      scan_timeout = 50;

      # ── Time ────────────────────────────────────────────────────
      time = {
        disabled = false;
        format = ''\[$time\]($style)'';
        style = "italic ${c.base03}";
        use_12hr = false;
        time_format = "%R";
      };

      # ── Hostname ────────────────────────────────────────────────
      hostname = {
        ssh_only = false;
        format = "[$hostname](bold ${c.base0B}) ";
        disabled = false;
      };

      # ── Directory ──────────────────────────────────────────────
      directory = {
        truncation_length = 3;
        truncation_symbol = "…/";
        style = "bold ${c.base0D}";
        fish_style_pwd_dir_length = 0;
      };

      # ── Git ────────────────────────────────────────────────────
      git_branch = {
        format = "on [$branch](italic ${c.base0D}) ";
        symbol = " ";
      };

      git_status = {
        format = "[($all_status$ahead_behind)](bold ${c.base0D}) ";
        ahead = "⇡";
        behind = "⇣";
        diverged = "⇕";
        conflicted = "✖";
        untracked = "•";
        modified = "▲";
        staged = "●";
        stashed = "≡";
      };

      # ── Nix Shell ─────────────────────────────────────────────
      nix_shell = {
        format = "[❄ $state($name)](bold ${c.base0A}) ";
        disabled = false;
        heuristic = true;
      };

      # ── Command Duration ──────────────────────────────────────
      cmd_duration = {
        format = "[⏱ $duration](italic ${c.base03})";
        show_milliseconds = false;
        min_time = 2000;
      };

      # ── Prompt Character ──────────────────────────────────────
      character = {
        success_symbol = "[╰─❯](bold ${c.base0D})";
        error_symbol = "[╰─✗](bold ${c.base08})";
        vicmd_symbol = "[╰─❮](bold ${c.base0B})";
      };

      # ── Fill line ─────────────────────────────────────────────
      fill = {
        symbol = "─";
        style = "${c.base02}";
      };

      # ── Misc ──────────────────────────────────────────────────
      command_timeout = 10000;

      sudo.disabled = true;
      username.disabled = true;
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
      package.disabled = true;
      dart.disabled = true;
      elixir.disabled = true;
      haxe.disabled = true;
      julia.disabled = true;
      lua.disabled = true;
      perl.disabled = true;
      php.disabled = true;
      scala.disabled = true;
      swift.disabled = true;
      zig.disabled = true;

      custom.miner = {
        command = minerScript;
        when = true;
        shell = ["bash" "-c"];
        format = "[$output](bold ${c.base0E}) ";
        disabled = false;
      };

      # ── Noctalia palette (Material You mapping from base16) ──────
      # Starship's `palette = "noctalia"` requires a [palettes.noctalia]
      # section. We derive it from the active Stylix base16 scheme so the
      # palette stays in sync with the theme. This replaces the drifted
      # plain-file starship.toml that referenced a non-existent palette.
      palette = lib.mkDefault "noctalia";
      palettes.noctalia = {
        # Surface hierarchy
        surface = c.base00;
        surface0 = c.base01;
        surface1 = c.base02;
        surface2 = c.base03;
        # Text
        text = c.base05;
        text0 = c.base04;
        text1 = c.base06;
        text2 = c.base07;
        # Accents (Material You roles)
        primary = c.base0D;   # blue
        secondary = c.base0B; # green
        tertiary = c.base0A;  # yellow
        error = c.base08;     # red
        warning = c.base09;   # orange
        magenta = c.base0E;   # magenta
        # Terminal 16-color aliases
        black = c.base00;
        red = c.base08;
        green = c.base0B;
        yellow = c.base0A;
        blue = c.base0D;
        purple = c.base0E;
        cyan = c.base0C;
        white = c.base05;
        bright-black = c.base03;
        bright-red = c.base08;
        bright-green = c.base0B;
        bright-yellow = c.base0A;
        bright-blue = c.base0D;
        bright-purple = c.base0E;
        bright-cyan = c.base0C;
        bright-white = c.base06;
      };
    };
  };
}
