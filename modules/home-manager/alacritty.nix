{
  programs.alacritty = {
    enable = true;

    settings = {
      env.TERM = "xterm-256color";

      shell.program = "fish";
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
        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Regular";
        };
        bold = {
          family = "JetBrainsMono Nerd Font";
          style = "Bold";
        };
        italic = {
          family = "JetBrainsMono Nerd Font";
          style = "Italic";
        };
        bold_italic = {
          family = "JetBrainsMono Nerd Font";
          style = "Bold Italic";
        };
      };

      keyboard.bindings = [
        {
          key = "Insert";
          mods = "Shift";
          action = "Paste";
        }
        {
          key = "Insert";
          mods = "Control";
          action = "Copy";
        }
        {
          key = "Return";
          mods = "Shift";
          chars = "\\u001B\\r";
        }
        # Numpad: force plain characters (fixes raw-mode TUI apps like OpenCode)
        # Without these, Alacritty sends application keypad escape sequences
        # in raw mode which most Go/Rust TUI frameworks silently drop.
        {
          key = "Numpad0";
          chars = "0";
        }
        {
          key = "Numpad1";
          chars = "1";
        }
        {
          key = "Numpad2";
          chars = "2";
        }
        {
          key = "Numpad3";
          chars = "3";
        }
        {
          key = "Numpad4";
          chars = "4";
        }
        {
          key = "Numpad5";
          chars = "5";
        }
        {
          key = "Numpad6";
          chars = "6";
        }
        {
          key = "Numpad7";
          chars = "7";
        }
        {
          key = "Numpad8";
          chars = "8";
        }
        {
          key = "Numpad9";
          chars = "9";
        }
        {
          key = "NumpadDecimal";
          chars = ".";
        }
        {
          key = "NumpadDivide";
          chars = "/";
        }
        {
          key = "NumpadMultiply";
          chars = "*";
        }
        {
          key = "NumpadSubtract";
          chars = "-";
        }
        {
          key = "NumpadAdd";
          chars = "+";
        }
        {
          key = "NumpadEnter";
          chars = "\\r";
        }
      ];
    };
  };
}
