# OpenCode Home Manager Configuration
# Moves opencode from nix profile to HM so:
# 1. The programs.opencode option namespace exists (required by stylix)
# 2. The package is managed declaratively
#
# Config split:
#   ~/.config/opencode/opencode.json — HM-managed (this file, minimal)
#   ~/.opencode/config.json — ai-coding-tools generator (providers, MCP, models)
{
  pkgs,
  lib,
  ...
}:
{
  programs.opencode = {
    enable = true;
    settings = {
      plugin = [ "oh-my-opencode@latest" ];
    };
  };

  # Stylix's opencode HM module sets programs.opencode.tui.theme = "stylix"
  # but the upstream HM opencode module doesn't declare a `tui` sub-option.
  # Disable the stylix target to prevent the error.
  stylix.targets.opencode.enable = false;
}
