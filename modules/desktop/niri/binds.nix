# Niri Keybindings
# Similar patterns to your Hyprland setup
_: {
  programs.niri.settings.binds = {
    # System keybindings
    "Super+Return".action.spawn = ["kitty"];

    "Super+W".action.close-window = [];

    "Super+D".action.spawn = [
      "rofi"
      "-show"
      "drun"
    ];

    # Workspaces
    "Super+1".action.workspace = 1;
    "Super+2".action.workspace = 2;
    "Super+3".action.workspace = 3;
    "Super+4".action.workspace = 4;
    "Super+5".action.workspace = 5;
    "Super+6".action.workspace = 6;
    "Super+7".action.workspace = 7;
    "Super+8".action.workspace = 8;
    "Super+9".action.workspace = 9;
    "Super+0".action.workspace = 10;

    # Move window to workspace
    "Super+Shift+1".action.move-window-to-workspace = 1;
    "Super+Shift+2".action.move-window-to-workspace = 2;
    "Super+Shift+3".action.move-window-to-workspace = 3;
    "Super+Shift+4".action.move-window-to-workspace = 4;
    "Super+Shift+5".action.move-window-to-workspace = 5;
    "Super+Shift+6".action.move-window-to-workspace = 6;
    "Super+Shift+7".action.move-window-to-workspace = 7;
    "Super+Shift+8".action.move-window-to-workspace = 8;
    "Super+Shift+9".action.move-window-to-workspace = 9;
    "Super+Shift+0".action.move-window-to-workspace = 10;

    # Media keys
    "XF86AudioRaiseVolume".action.spawn = [
      "pamixer"
      "-i"
      "5"
    ];
    "XF86AudioLowerVolume".action.spawn = [
      "pamixer"
      "-d"
      "5"
    ];
    "XF86AudioMute".action.spawn = [
      "pamixer"
      "-t"
    ];

    "XF86MonBrightnessUp".action.spawn = [
      "brightnessctl"
      "set"
      "5%+"
    ];
    "XF86MonBrightnessDown".action.spawn = [
      "brightnessctl"
      "set"
      "5%-"
    ];

    # Screenshots
    "Print".action.spawn = [
      "grim"
      "-"
      "wl-copy"
    ];

    "Super+Print".action.spawn = [
      "grim"
      "-g"
      "$(slurp)"
      "-"
      "wl-copy"
    ];
  };
}
