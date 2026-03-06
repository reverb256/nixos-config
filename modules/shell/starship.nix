# Starship Prompt Module
# Enhanced starship configuration for productivity
{
  pkgs,
  config,
  ...
}: {
  # Enable Starship prompt
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

      # Format
      format = "$directory$git_branch$git_status$character";

      # Timeout for commands
      command_timeout = 10000;

      # Directories
      directory = {
        truncation_length = 2;
        truncation_symbol = "…/";
        repo_root_style = "bold cyan";
        repo_root_format = "[$path]($style)[$read_only]($read_only_style) ";
        read_only = " 🔒";
        style = "bold cyan";
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

      # Disable unused modules
      nix_shell.disabled = true;
      docker_context.disabled = true;
      sudo.disabled = true;
    };
  };

  # Tokyo Night Dark theme colors for Starship
  # (Stylix handles the actual theming, this is for reference)
  # Colors from Tokyo Night:
  # - Background: #1a1b26
  # - Current Line: #7aa2f7
  # - Foreground: #c0caf5
  # - Comment: #565f89
  # - Cyan: #2ac3de
  # - Green: #9ece6a
  # - Orange: #ff9e64
  # - Pink: #bb9af7
  # - Purple: #9d7cd8
  # - Red: #f7768e
  # - Yellow: #e0af68
}
