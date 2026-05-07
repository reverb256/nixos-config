{
  programs.alacritty = {
    enable = true;

    settings = {
      env.TERM = "xterm-256color";

      terminal.osc52 = "CopyPaste";

      window = {
        padding = {
          x = 8;
          y = 4;
        };
        decorations = "none";
        opacity = 0.95;
      };

      scrolling.history = 10000;

      selection.save_to_clipboard = true;

      cursor = {
        style.shape = "Block";
        unfocused_hollow = true;
      };

      mouse.hide_when_typing = true;

      font = {
        size = 12;
        normal = { family = "JetBrainsMono Nerd Font"; style = "Regular"; };
        bold = { family = "JetBrainsMono Nerd Font"; style = "Bold"; };
        italic = { family = "JetBrainsMono Nerd Font"; style = "Italic"; };
        bold_italic = { family = "JetBrainsMono Nerd Font"; style = "Bold Italic"; };
      };

      keyboard.bindings = [
        { key = "Insert"; mods = "Shift"; action = "Paste"; }
        { key = "Insert"; mods = "Control"; action = "Copy"; }
        { key = "Return"; mods = "Shift"; chars = "\\u001B\\r"; }
      ];
    };
  };
}
