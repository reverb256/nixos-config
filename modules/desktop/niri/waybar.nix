# Waybar configuration for Niri
# Compatible with Niri's protocols and workspaces
{
  mainBar = {
    layer = "top";
    position = "top";
    height = 30;
    spacing = 4;

    modules-left = ["niri/workspaces" "wlr/taskbar"];
    modules-center = ["clock"];
    modules-right = ["tray" "pulseaudio" "network" "cpu" "memory" "battery"];

    "niri/workspaces" = {
      all-outputs = true;
      format = "{name}";
    };

    "wlr/taskbar" = {
      format = "{icon}";
      icon-size = 18;
      tooltip-format = "{title}";
      on-click = "activate";
      on-click-middle = "close";
    };

    "clock" = {
      format = "{:%H:%M}";
      tooltip-format = "<big>{:%Y-%m-%d}</big>\n<tt><small>{calendar}</small></tt>";
    };

    "pulseaudio" = {
      format = "{icon} {volume}%";
      format-muted = "󰝟";
      format-icons = {
        default = ["󰕿" "󰖀" "󰕾"];
      };
      on-click = "pavucontrol";
    };

    "network" = {
      format-wifi = "󰖩 {signalStrength}%";
      format-ethernet = "󰈀 {ipaddr}";
      format-disconnected = "󰖪";
    };

    "cpu" = {
      format = "󰻠 {usage}%";
      interval = 2;
    };

    "memory" = {
      format = "󰍛 {}%";
      interval = 2;
    };

    "battery" = {
      states = {
        warning = 30;
        critical = 15;
      };
      format = "{icon} {capacity}%";
      format-charging = "󰂄 {capacity}%";
      format-icons = ["󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
    };

    "tray" = {
      icon-size = 18;
      spacing = 4;
    };
  };
}
