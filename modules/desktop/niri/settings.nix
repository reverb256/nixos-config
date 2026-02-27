# Niri Settings - Core configuration
_: {
  programs.niri.settings = {
    # Monitor configuration
    # Match your current 4-monitor setup from Hyprland
    output = {
      "DP-2" = {
        position = {
          x = 0;
          y = 0;
        };
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60;
        };
      };
      "DP-1" = {
        position = {
          x = 1920;
          y = 0;
        };
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60;
        };
      };
      "DP-3" = {
        position = {
          x = 1920;
          y = 1080;
        };
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60;
        };
      };
      "HDMI-A-1" = {
        position = {
          x = 3840;
          y = 0;
        };
        mode = {
          width = 3840;
          height = 2160;
          refresh = 60;
        };
      };
    };

    # Input configuration
    input = {
      keyboard = {
        repeat-delay = 300;
        repeat-rate = 50;
        track-layout = "window";
      };

      touchpad = {
        tap-to-click = true;
        dwt = true;
        disable-while-typing = true;
        natural-scroll = true;
      };

      mouse = {
        natural-scroll = false;
      };
    };

    # Layout configuration
    layout = {
      gaps = 5; # Match your current Hyprland setup
      border.width = 2;

      focus-ring = {
        width = 2;
        active.color = "#539afc"; # Tokyo Night accent
        inactive.color = "#526270"; # Tokyo Night muted
      };

      struts = {
        left = 0;
        right = 0;
        top = 0;
        bottom = 0;
      };
    };

    # Window rules
    window-rule = [
      # Floating windows
      {
        matches = [
          {app-id = "^pavucontrol$";}
        ];
        float = true;
      }
    ];
  };
}
