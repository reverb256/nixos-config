# Niri Window Manager Configuration
# Typed settings for sodiboo/niri-flake integration
# Uses: programs.niri.settings (home-manager module auto-propagated by nixosModules.niri)
#
# Companion infrastructure (portal, tools, NVIDIA) is in modules/desktop/niri.nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkDefault mkIf;
  # Check if niri home-manager module is loaded (provides lib.niri.actions)
  niriHmAvailable = config.lib ? niri;
in {
  # Only configure niri settings when the HM module is actually available
  programs.niri.settings = mkIf niriHmAvailable (let
    acts = config.lib.niri.actions;
  in {
    # ==========================================================================
    # GENERAL SETTINGS
    # ==========================================================================
    spawn-at-startup = [
      {argv = ["${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"];}
      {argv = ["${pkgs.mako}/bin/mako"];}
      {argv = ["${pkgs.waybar}/bin/waybar"];}
      {argv = ["${pkgs.swww}/bin/swww" "img" (builtins.getEnv "HOME" + "/.config/wallpaper.png")];}
      {sh = "wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store";}
      {sh = "wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store";}
    ];

    # Cursor configuration
    cursor = {
      theme = mkDefault "Adwaita";
      size = mkDefault 24;
      hide-on-key-press = true;
      hide-after-inactive-ms = 3000;
    };

    # Hot corner overlay (for exiting fullscreen)
    hotkey-overlay = {
      skip-at-startup = false;
    };

    # Disable client-side decorations where possible
    prefer-no-csd = true;

    # ==========================================================================
    # LAYOUT (focus-ring, border, column widths)
    # ==========================================================================
    layout = {
      focus-ring = {
        enable = true;
        width = 2;
        active = {color = "#7aa2f7";}; # Tokyo Night blue
        inactive = {color = "#3b4261";}; # Tokyo Night comment
      };

      border = {
        enable = false;
        width = 1;
        active = {color = "#7aa2f7";};
        inactive = {color = "#3b4261";};
      };

      # Default column width for new windows (50% of screen)
      default-column-width = {proportion = 0.5;};

      # Center the focused column
      center-focused-column = "never";

      # Gaps between windows
      gaps = 8;
    };

    # ==========================================================================
    # OUTPUT/MONITOR CONFIGURATION
    # ==========================================================================
    outputs = {
      # Default output configuration (applies to all monitors)
      "*" = {
        scale = 1.0;
      };

      # Zephyr monitor layout (from plasma6.nix kscreen config)
      # DP-5: ZOWIE primary gaming monitor (1920x1080)
      "DP-5" = {
        mode = {width = 1920; height = 1080; refresh = 144.0;};
        position = {x = 0; y = 349;};
        scale = 1.0;
      };

      # DP-4: ASUS top monitor (1920x1080)
      "DP-4" = {
        mode = {width = 1920; height = 1080; refresh = 75.0;};
        position = {x = 1920; y = 0;};
        scale = 1.0;
      };

      # DP-6: Acer X203H bottom monitor (1600x900)
      "DP-6" = {
        mode = {width = 1600; height = 900; refresh = 60.0;};
        position = {x = 1920; y = 1080;};
        scale = 1.0;
      };

      # HDMI-A-2: Samsung 4K HDR TV
      "HDMI-A-2" = {
        mode = {width = 3840; height = 2160; refresh = 60.0;};
        position = {x = 3520; y = 1080;};
        scale = 1.5;
      };
    };

    # ==========================================================================
    # INPUT DEVICE CONFIGURATION
    # ==========================================================================
    input = {
      keyboard = {
        xkb = {
          layout = "us";
          variant = "";
          options = "caps:escape"; # Caps Lock as Escape
        };
        repeat-delay = 300;
        repeat-rate = 50;
        numlock = true;
        track-layout = "global";
      };

      touchpad = {
        tap = true;
        dwt = true;
        dwtp = true;
        natural-scroll = true;
        click-method = "clickfinger";
        accel-speed = 0.0;
        accel-profile = "adaptive";
        scroll-method = "two-finger";
        scroll-button = 274;
        middle-emulation = false;
        left-handed = false;
        disabled-on-external-mouse = false;
      };

      mouse = {
        natural-scroll = false;
        accel-speed = 0.0;
        accel-profile = "adaptive";
        scroll-method = "no-scroll";
        scroll-button = 274;
        middle-emulation = false;
        left-handed = false;
      };

      trackpoint = {
        natural-scroll = true;
        accel-speed = 0.0;
        accel-profile = "flat";
        scroll-method = "on-button-down";
        scroll-button = 274;
        middle-emulation = false;
      };

      tablet = {
        map-to-output = null;
      };

      focus-follows-mouse = {
        max-scroll-amount = "0.5";
      };

      warp-mouse-to-focus.enable = true;
    };

    # ==========================================================================
    # KEY BINDINGS (using niri action helpers)
    # ==========================================================================
    binds = with acts; {
      # --------------------------------------------------------------------------
      # SPAWN APPLICATIONS
      # --------------------------------------------------------------------------
      "Mod+Return".action = spawn "${pkgs.kdePackages.konsole}/bin/konsole";
      "Mod+D".action = spawn "${pkgs.fuzzel}/bin/fuzzel";
      "Mod+Space".action = spawn "${pkgs.fuzzel}/bin/fuzzel";
      "Mod+E".action = spawn "${pkgs.kdePackages.dolphin}/bin/dolphin";
      "Mod+B".action = spawn "${pkgs.firefox}/bin/firefox";
      "Mod+Shift+E".action = spawn "${pkgs.vscode}/bin/code";
      "Mod+Print".action = spawn "${pkgs.grim}/bin/grim" "-g" "$(${pkgs.slurp}/bin/slurp)";
      "Mod+Shift+Print".action = spawn "${pkgs.grim}/bin/grim";

      # --------------------------------------------------------------------------
      # WINDOW MANAGEMENT
      # --------------------------------------------------------------------------
      "Mod+Q".action = close-window;
      "Mod+Left".action = focus-column-left;
      "Mod+Right".action = focus-column-right;
      "Mod+Up".action = focus-window-up;
      "Mod+Down".action = focus-window-down;
      "Mod+H".action = focus-column-left;
      "Mod+L".action = focus-column-right;
      "Mod+K".action = focus-window-up;
      "Mod+J".action = focus-window-down;

      # Move windows (Vim-style)
      "Mod+Shift+Left".action = move-column-left;
      "Mod+Shift+Right".action = move-column-right;
      "Mod+Shift+Up".action = move-window-up;
      "Mod+Shift+Down".action = move-window-down;
      "Mod+Shift+H".action = move-column-left;
      "Mod+Shift+L".action = move-column-right;
      "Mod+Shift+K".action = move-window-up;
      "Mod+Shift+J".action = move-window-down;

      # Column width adjustment
      "Mod+Comma".action = consume-window-into-column;
      "Mod+Period".action = expel-window-from-column;
      "Mod+R".action = switch-preset-column-width;
      "Mod+Shift+R".action = reset-window-height;
      "Mod+Minus".action = set-column-width "-10%";
      "Mod+Equal".action = set-column-width "+10%";
      "Mod+Shift+Minus".action = set-window-height "-10%";
      "Mod+Shift+Equal".action = set-window-height "+10%";

      # Center focused column
      "Mod+C".action = center-column;

      # Focus and move to monitor edges
      "Mod+Home".action = focus-column-first;
      "Mod+End".action = focus-column-last;
      "Mod+Shift+Home".action = move-column-to-first;
      "Mod+Shift+End".action = move-column-to-last;

      # --------------------------------------------------------------------------
      # WORKSPACE MANAGEMENT
      # --------------------------------------------------------------------------
      "Mod+1".action = focus-workspace 1;
      "Mod+2".action = focus-workspace 2;
      "Mod+3".action = focus-workspace 3;
      "Mod+4".action = focus-workspace 4;
      "Mod+5".action = focus-workspace 5;
      "Mod+6".action = focus-workspace 6;
      "Mod+7".action = focus-workspace 7;
      "Mod+8".action = focus-workspace 8;
      "Mod+9".action = focus-workspace 9;
      "Mod+0".action = focus-workspace 10;

      # Move window to workspace (no action helper, use raw format)
      "Mod+Shift+1".action.move-column-to-workspace = 1;
      "Mod+Shift+2".action.move-column-to-workspace = 2;
      "Mod+Shift+3".action.move-column-to-workspace = 3;
      "Mod+Shift+4".action.move-column-to-workspace = 4;
      "Mod+Shift+5".action.move-column-to-workspace = 5;
      "Mod+Shift+6".action.move-column-to-workspace = 6;
      "Mod+Shift+7".action.move-column-to-workspace = 7;
      "Mod+Shift+8".action.move-column-to-workspace = 8;
      "Mod+Shift+9".action.move-column-to-workspace = 9;
      "Mod+Shift+0".action.move-column-to-workspace = 10;

      # Workspace navigation
      "Mod+Page_Down".action = focus-workspace-down;
      "Mod+Page_Up".action = focus-workspace-up;
      "Mod+Shift+Page_Down".action = move-column-to-workspace-down;
      "Mod+Shift+Page_Up".action = move-column-to-workspace-up;
      "Mod+BracketLeft".action = focus-workspace-down;
      "Mod+BracketRight".action = focus-workspace-up;

      # --------------------------------------------------------------------------
      # MONITOR/OUTPUT MANAGEMENT
      # --------------------------------------------------------------------------
      "Mod+Ctrl+Left".action = focus-monitor-left;
      "Mod+Ctrl+Right".action = focus-monitor-right;
      "Mod+Ctrl+Up".action = focus-monitor-up;
      "Mod+Ctrl+Down".action = focus-monitor-down;
      "Mod+Ctrl+H".action = focus-monitor-left;
      "Mod+Ctrl+L".action = focus-monitor-right;
      "Mod+Ctrl+K".action = focus-monitor-up;
      "Mod+Ctrl+J".action = focus-monitor-down;

      # Move window to monitor
      "Mod+Ctrl+Shift+Left".action = move-column-to-monitor-left;
      "Mod+Ctrl+Shift+Right".action = move-column-to-monitor-right;
      "Mod+Ctrl+Shift+Up".action = move-column-to-monitor-up;
      "Mod+Ctrl+Shift+Down".action = move-column-to-monitor-down;
      "Mod+Ctrl+Shift+H".action = move-column-to-monitor-left;
      "Mod+Ctrl+Shift+L".action = move-column-to-monitor-right;
      "Mod+Ctrl+Shift+K".action = move-column-to-monitor-up;
      "Mod+Ctrl+Shift+J".action = move-column-to-monitor-down;

      # --------------------------------------------------------------------------
      # WINDOW STATE
      # --------------------------------------------------------------------------
      "Mod+F".action = fullscreen-window;
      "Mod+V".action = toggle-window-floating;
      "Mod+Shift+V".action = switch-focus-between-floating-and-tiling;

      # --------------------------------------------------------------------------
      # LAYOUT CYCLING
      # --------------------------------------------------------------------------
      "Mod+Tab".action = focus-workspace-down;
      "Mod+Shift+Tab".action = focus-workspace-up;

      # --------------------------------------------------------------------------
      # CLIPBOARD (uses shell for pipe)
      # --------------------------------------------------------------------------
      "Mod+Ctrl+V".action = spawn "sh" "-c" "${pkgs.cliphist}/bin/cliphist list | ${pkgs.fuzzel}/bin/fuzzel --dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy";

      # --------------------------------------------------------------------------
      # MEDIA CONTROLS
      # --------------------------------------------------------------------------
      "XF86AudioRaiseVolume".action = spawn "${pkgs.pamixer}/bin/pamixer" "-i" "5";
      "XF86AudioLowerVolume".action = spawn "${pkgs.pamixer}/bin/pamixer" "-d" "5";
      "XF86AudioMute".action = spawn "${pkgs.pamixer}/bin/pamixer" "--toggle-mute";
      "XF86AudioMicMute".action = spawn "${pkgs.pamixer}/bin/pamixer" "--default-source" "--toggle-mute";
      "XF86MonBrightnessUp".action = spawn "${pkgs.brightnessctl}/bin/brightnessctl" "set" "+5%";
      "XF86MonBrightnessDown".action = spawn "${pkgs.brightnessctl}/bin/brightnessctl" "set" "5%-";
      "XF86AudioPlay".action = spawn "${pkgs.playerctl}/bin/playerctl" "play-pause";
      "XF86AudioNext".action = spawn "${pkgs.playerctl}/bin/playerctl" "next";
      "XF86AudioPrev".action = spawn "${pkgs.playerctl}/bin/playerctl" "previous";
      "XF86AudioStop".action = spawn "${pkgs.playerctl}/bin/playerctl" "stop";

      # --------------------------------------------------------------------------
      # SYSTEM ACTIONS
      # --------------------------------------------------------------------------
      "Mod+Shift+Escape".action = quit;
      "Mod+Escape".action = spawn "${pkgs.swaylock}/bin/swaylock";

      # Power menu (via fuzzel)
      "Mod+Shift+P".action = spawn "sh" "-c" "${pkgs.fuzzel}/bin/fuzzel --dmenu --prompt='Power:' <<< 'Lock\\nLogout\\nSuspend\\nReboot\\nShutdown' | ${pkgs.findutils}/bin/xargs -I{} sh -c 'case {} in Lock) ${pkgs.swaylock}/bin/swaylock;; Logout) niri msg action quit;; Suspend) systemctl suspend;; Reboot) systemctl reboot;; Shutdown) systemctl poweroff;; esac'";

      # Suspend
      "Mod+Ctrl+Escape".action = spawn "systemctl" "suspend";

      # --------------------------------------------------------------------------
      # NIRI ACTIONS
      # --------------------------------------------------------------------------
      "Mod+Shift+D".action.toggle-debug-tint = [];
      "Mod+Shift+C".action.reload-config = [];
      "Mod+Slash".action.show-hotkey-overlay = [];
    };

    # ==========================================================================
    # WINDOW RULES
    # ==========================================================================
    window-rules = [
      # Float specific applications
      {
        matches = [
          {app-id = "pavucontrol";}
          {app-id = "nm-connection-editor";}
          {app-id = "blueman-manager";}
          {app-id = "gnome-calculator";}
          {app-id = "gnome-control-center";}
          {app-id = "file-roller";}
          {title = "File Transfer*";}
          {title = "Copy*";}
          {title = "Passwords*";}
          {app-id = "pinentry-";}
        ];
        open-floating = true;
      }

      # Picture-in-Picture windows
      {
        matches = [{title = "Picture-in-Picture";}];
        open-floating = true;
        default-floating-position = {x = 0; y = 0; relative-to = "top-left";};
        default-column-width = {fixed = 400;};
        default-window-height = {fixed = 225;};
      }

      # Full-width applications
      {
        matches = [
          {app-id = "firefox";}
          {app-id = "librewolf";}
          {app-id = "chromium";}
          {app-id = "brave";}
        ];
        default-column-width = {proportion = 1.0;};
      }

      # Terminal default width
      {
        matches = [
          {app-id = "Alacritty";}
          {app-id = "kitty";}
          {app-id = "foot";}
          {app-id = "gnome-terminal";}
          {app-id = "konsole";}
        ];
        default-column-width = {proportion = 0.5;};
      }

      # IDEs and editors
      {
        matches = [
          {app-id = "code";}
          {app-id = "code-url-handler";}
          {app-id = "jetbrains-";}
          {app-id = "emacs";}
        ];
        default-column-width = {proportion = 0.7;};
      }

      # Games (usually want floating or fullscreen)
      {
        matches = [
          {app-id = "steam";}
          {app-id = "lutris";}
          {app-id = "heroic";}
          {app-id = "minecraft";}
          {app-id = "prism-launcher";}
        ];
        open-floating = true;
      }

      # Screen sharing prompts (always float, no border)
      {
        matches = [{title = "Choose what to share";}];
        open-floating = true;
      }

      # Block screen-sharing of sensitive windows
      {
        matches = [
          {app-id = "bitwarden";}
          {app-id = "keepassxc";}
          {app-id = "1password";}
          {title = "*Password*";}
          {title = "*Secret*";}
        ];
        block-out-from = "screen-capture";
      }
    ];

    # ==========================================================================
    # LAYER RULES
    # ==========================================================================
    layer-rules = [
      # Waybar - always visible
      {
        matches = [{namespace = "waybar";}];
        place-within-backdrop = false;
      }

      # Mako notifications
      {
        matches = [{namespace = "mako";}];
        place-within-backdrop = false;
      }

      # Fuzzel launcher
      {
        matches = [{namespace = "fuzzel";}];
        place-within-backdrop = false;
      }

      # GTK layer shell apps
      {
        matches = [{namespace = "gtk-layer-shell";}];
        place-within-backdrop = false;
      }

      # Screen lock (above everything)
      {
        matches = [{namespace = "swaylock";}];
        place-within-backdrop = true;
      }
    ];
  });
}
