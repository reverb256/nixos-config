# Ghostty Terminal Configuration
# Fast, native Wayland terminal designed for tiling window managers
# Theme/fonts handled by Stylix (autoEnable = true)
{
  programs.ghostty = {
    enable = true;

    settings = {
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

    };
  };
}
