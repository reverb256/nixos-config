# OpenCode Home Manager Configuration
# Moves opencode from nix profile to HM so:
# 1. The programs.opencode option namespace exists (required by stylix)
# 2. The package is managed declaratively
#
# Config split:
#   ~/.config/opencode/opencode.json — HM-managed (plugins, theme)
#   ~/.opencode/config.json — ai-coding-tools generator (providers, MCP, models)
#
# HM PR #9025 added programs.opencode.tui for opencode v1.2.15+
# Stylix PR #2268 migrated to use programs.opencode.tui.theme
{pkgs, ...}: {
  programs.opencode = {
    enable = true;
    settings = {
      plugin = ["oh-my-opencode@latest"];
    };
  };

  # Telegram desktop — moved from nix profile
  home.packages = [pkgs.telegram-desktop];
}
