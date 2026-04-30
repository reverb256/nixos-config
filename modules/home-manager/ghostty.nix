{
  programs.ghostty = {
    enable = true;

    settings = {
      window-padding-x = 8;
      window-padding-y = 4;
      window-decoration = false;

      confirm-close-surface = false;
      copy-on-select = "clipboard";
      mouse-hide-while-typing = true;
      clipboard-read = "allow";
      clipboard-write = "allow";

      scrollback-limit = 10000;

      cursor-style = "block";
      cursor-style-blink = false;
    };
  };
}
