{ config, pkgs, lib, ... }:
let
  c = config.lib.stylix.colors.withHashtag;

  # miner script removed — was broken
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
    };
  };
}