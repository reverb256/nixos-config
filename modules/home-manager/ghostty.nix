# Ghostty Terminal Configuration
# Fast, native Wayland terminal designed for tiling window managers
{ config, ... }:
{
  programs.ghostty = {
    enable = true;

    settings = {
      # Theme
      theme = "tokyo-night";

      # Font
      font-family = "JetBrainsMono Nerd Font";
      font-size = 12;

      # Window
      window-padding-x = 8;
      window-padding-y = 4;
      window-decoration = false; # No CSD — niri draws borders

      # Behavior
      confirm-close-surface = false;
      copy-on-select = "clipboard";
      mouse-hide-while-typing = true;
      clipboard-read = "allow";
      clipboard-write = "allow";

      # Scrollback
      scrollback-limit = 10000;

      # Cursor
      cursor-style = "block";
      cursor-style-blink = false;

      # Performance
      adaptive-square-shader = true;
    };
  };
}
