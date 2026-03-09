# Starship Prompt Configuration (Home Manager)
# Centralized starship settings for j_kro across all cluster nodes
{...}: {
  programs.starship = {
    enable = true;

    settings = {
      # Add a new line between prompts
      add_newline = false;

      # Character
      character = {
        success_symbol = "[❯](bold cyan)";
        error_symbol = "[✗](bold red)";
        vicmd_symbol = "[❮](bold green)";
      };

      # Format - optimized for cluster workflow
      # hostname branch git_status nix_shell character
      format = "$hostname$git_branch$git_status$nix_shell$character";

      # Timeout for commands
      command_timeout = 10000;

      # Hostname - show cluster node name
      hostname = {
        ssh_only = false;
        format = "[$hostname]($style) ";
        style = "bold green";
        disabled = false;
      };

      # Username - completely disabled
      username = {
        show_always = false;
        disabled = true;
      };

      # Directories
      directory = {
        truncation_length = 3;
        truncation_symbol = "…/";
        repo_root_style = "bold cyan";
        repo_root_format = "[$path]($style)[$read_only]($read_only_style) ";
        read_only = " 🔒";
        style = "bold cyan";
        fish_style_pwd_rooted = "bold cyan";
      };

      # Git
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

      # Nix shell - show "local" when not in shell, shell name when in shell
      nix_shell = {
        symbol = "";
        format = "[local ]($style)";
        style = "bold dimmed white";
        disabled = false;
        heuristic = true;
      };

      # Disable unused modules to keep prompt clean
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
