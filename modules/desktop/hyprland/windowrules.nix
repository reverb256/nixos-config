# Hyprland Window Rules
{ ... }:
{
  wayland.windowManager.hyprland.settings = {
    windowrule = [
      # ============================================================
      # FLOATING WINDOWS (Dialogs, utilities, etc.)
      # ============================================================
      "float, class:^(pavucontrol)$"
      "float, class:^(nm-connection-editor)$"
      "float, class:^(blueman-manager)$"
      "float, class:^(org.gnome.Calculator)$"
      "float, class:^(org.gnome.FileRoller)$"
      "float, class:^(File Transfer)$"
      "float, class:^(file_progress)$"
      "float, class:^(confirm)$"
      "float, class:^(dialog)$"
      "float, class:^(download)$"
      "float, class:^(notification)$"
      "float, class:^(error)$"
      "float, class:^(confirmreset)$"
      "float, title:^(Open File)$"
      "float, title:^(File Upload)$"
      "float, title:^(branchdialog)$"
      "float, title:^(Confirm to replace files)$"
      "float, title:^(File Operation Progress)$"
      "float, title:^(Save As)$"

      # ============================================================
      # PICTURE-IN-PICTURE (Video players)
      # ============================================================
      "float, title:^(Picture-in-Picture)$"
      "opacity 1.0 override, title:^(Picture-in-Picture)$"
      "pin, title:^(Picture-in-Picture)$"
      "stayfocused, title:^(Picture-in-Picture)$"

      # ============================================================
      # MEDIA PLAYERS
      # ============================================================
      "idleinhibit focus, class:^(mpv)$"
      "idleinhibit focus, class:^(vlc)$"
      "idleinhibit fullscreen, class:^(firefox)$"
      "idleinhibit fullscreen, class:^(chromium)$"

      # ============================================================
      # WORKSPACE ASSIGNMENTS
      # ============================================================
      # Web browsers
      "workspace 1, class:^(firefox)$"
      "workspace 1, class:^(chromium)$"
      "workspace 1, class:^(vivaldi)$"

      # Code editors / IDEs
      "workspace 2, class:^(codium)$"
      "workspace 2, class:^(code-oss)$"
      "workspace 2, class:^(neovim)$"

      # Communication
      "workspace 10, class:^(discord)$"
      "workspace 10, class:^(WebCord)$"
      "workspace 10, class:^(telegramdesktop)$"
      "workspace 10, class:^(vesktop)$"

      # Games
      "workspace 4, class:^(Steam)$"
      "workspace 4, class:^(heroic)$"
      "workspace 4, class:^(Lutris)$"
      "workspace 4, title:^(Steam.*)"

      # Graphics / Media
      "workspace 5, class:^(Gimp)$"
      "workspace 5, class:^(Inkscape)$"
      "workspace 5, class:^(obsidian)$"
      "workspace 5, class:^(kdenlive)$"
      "workspace 5, class:^(com.obsproject.Studio)$"

      # ============================================================
      # SIZE & POSITION RULES
      # ============================================================
      "size 800 600, class:^(pavucontrol)$"
      "size 800 600, class:^(nm-connection-editor)$"
      "size 40% 40%, class:^(file_progress)$"

      # Center specific windows
      "center, class:^(org.gnome.Calculator)$"

      # ============================================================
      # OPACITY & VISUAL EFFECTS
      # ============================================================
      "opacity 0.9, class:^(discord)$"
      "opacity 0.9, class:^(WebCord)$"
      "opacity 0.95, class:^(code-oss)$"
      "opacity 0.95, class:^(codium)$"

      # Remove transparency from some apps
      "opaque, class:^(kitty)$"
      "opaque, class:^(Alacritty)$"

      # ============================================================
      # STEAM & GAMES
      # ============================================================
      "fullscreen, title:^(Steam.*)"
      "fullscreen, class:^(steam_app.*)"

      # Fix Steam games issues
      "immediate, class:^(steam_app)$"

      # ============================================================
      # NO BLUR / SHADOW (Performance)
      # ============================================================
      "noblur, class:^(steam_app)$"
      "noshadow, class:^(steam_app)$"
      "noblur, class:^(vscode)$"
    ];

    # Layer rules (for special UI elements)
    layerrule = [
      "dimaround, rofi"
      "dimaround, wlogout"
      "dimaround, mode"
      "noanim, rofi"
    ];

    # Workspace-specific settings
    workspace = [
      # No gaps when only one window on workspace 1-3
      "w[t1], gapsout:0, gapsin:0"
      "w[tg1], gapsout:0, gapsin:0"
      "f[1], gapsout:0, gapsin:0"
    ];
  };
}
