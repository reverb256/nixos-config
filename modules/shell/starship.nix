# Starship Prompt Module
# Enhanced starship configuration for productivity
{pkgs, ...}: {
  # Enable Starship prompt for both Fish and Bash
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
      format = "$hostname$username$directory$git_branch$git_status$kubernetes$character";

      # Timeout for commands
      command_timeout = 10000;

      # Hostname - show cluster node name
      hostname = {
        ssh_only = false;
        ssh_symbol = "🌐 ";
        format = "[$hostname]($style) ";
        style = "bold dimmed green";
        disabled = false;
      };

      # Username
      username = {
        show_always = false;
        format = "[$user]($style) ";
        style_user = "bold yellow";
        disabled = false;
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
        truncation_symbol = "…/";
      };

      # Git
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

      # Kubernetes module - show cluster context
      kubernetes = {
        symbol = "☸ ";
        format = "[$context]($style) ";
        style = "bold blue";
        disabled = false;
      };

      # Nix shell - show when in nix-shell
      nix_shell = {
        symbol = "❄️ ";
        format = "[$state]($style) ";
        style = "bold purple";
        disabled = false;
        heuristic = true;
      };

      # Show container runtime
      docker_context = {
        symbol = "🐳 ";
        format = "[$context]($style) ";
        style = "bold blue";
        disabled = false;
      };

      # Node.js - show when in Node projects
      nodejs = {
        symbol = "⬢ ";
        format = "[$version]($style) ";
        style = "bold green";
        disabled = false;
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
    };
  };

  # Install Starship (also installed in fish.nix, but ensure it's available)
  environment.systemPackages = with pkgs; [starship];
}
