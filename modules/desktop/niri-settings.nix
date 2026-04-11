# Niri Window Manager Configuration
# Comprehensive settings for sodiboo/niri-flake integration
# Used with: programs.niri.enable = true; programs.niri.settings = { ... };
#
# This module provides the actual niri compositor settings (keybinds, outputs, input)
# The companion infrastructure (portal, tools, NVIDIA) is in niri.nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkDefault;
  # Helper: noctalia IPC commands
  noctalia =
    cmd:
    [
      "noctalia-shell"
      "ipc"
      "call"
    ]
    ++ (lib.splitString " " cmd);
in
{
  programs.niri.settings = lib.mkIf (config.programs.niri.enable or false) {
    # ==========================================================================
    # GENERAL SETTINGS
    # ==========================================================================
    spawn-at-startup = [
      # Polkit authentication agent (systemd also handles this)
      { command = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"; }
      # Noctalia desktop shell (replaces waybar, mako, fuzzel, swww)
      { command = "noctalia-shell"; }
      # Clipboard manager (requires wl-clipboard)
      { command = "wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store"; }
      { command = "wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store"; }
    ];

    # Cursor configuration
    cursor = {
      xcursor-theme = mkDefault "Adwaita";
      xcursor-size = mkDefault 24;
      hide-when-typing = true;
      hide-after-inactive-ms = 3000;
    };

    # Hot corner overlay (for exiting fullscreen)
    hotkey-overlay = {
      skip-at-startup = false;
    };

    # Focus ring and border configuration
    focus-ring = {
      enable = true;
      width = 2;
      active.color = "#7aa2f7"; # Tokyo Night blue
      inactive.color = "#3b4261"; # Tokyo Night comment
    };

    # Window border configuration
    border = {
      enable = false;
      width = 1;
      active.color = "#7aa2f7";
      inactive.color = "#3b4261";
    };

    # Preferred cursor theme
    prefer-no-csd = true; # Disable client-side decorations where possible

    # ==========================================================================
    # OUTPUT/MONITOR CONFIGURATION
    # ==========================================================================
    # Auto-detect outputs - configure specific monitors per-host
    # Override in host-specific configuration for multi-monitor setups
    outputs = {
      # Default output configuration (applies to all monitors)
      "*" = {
        scale = 1.0;
        transform = "normal";
        variable-refresh-rate = false;
      };

      # Zephyr monitor layout (from plasma6.nix kscreen config)
      # DP-5: ZOWIE primary gaming monitor (1920x1080)
      "DP-5" = {
        mode = {
          width = 1920;
          height = 1080;
          refresh = 144.0;
        };
        position = {
          x = 0;
          y = 349;
        };
        scale = 1.0;
      };

      # DP-4: ASUS top monitor (1920x1080)
      "DP-4" = {
        mode = {
          width = 1920;
          height = 1080;
          refresh = 75.0;
        };
        position = {
          x = 1920;
          y = 0;
        };
        scale = 1.0;
      };

      # DP-6: Acer X203H bottom monitor (1600x900)
      "DP-6" = {
        mode = {
          width = 1600;
          height = 900;
          refresh = 60.0;
        };
        position = {
          x = 1920;
          y = 1080;
        };
        scale = 1.0;
      };

      # HDMI-A-2: Samsung 4K HDR TV
      "HDMI-A-2" = {
        mode = {
          width = 3840;
          height = 2160;
          refresh = 60.0;
        };
        position = {
          x = 3520;
          y = 1080;
        };
        scale = 1.5;
      };
    };

    # ==========================================================================
    # INPUT DEVICE CONFIGURATION
    # ==========================================================================
    input = {
      # Keyboard settings
      keyboard = {
        xkb = {
          layout = "us";
          variant = "";
          options = "caps:escape"; # Caps Lock as Escape
        };
        # Repeat rate and delay for held keys
        repeat-delay = 300;
        repeat-rate = 50;
        # NumLock state on startup
        numlock = true;
        # Track layout changes
        track-layout = "global";
      };

      # Touchpad settings (for laptops)
      touchpad = {
        tap = true; # Tap to click
        dwt = true; # Disable while typing
        dwtp = true; # Disable while trackpointing
        natural-scroll = true; # Inverted scroll direction
        click-method = "clickfinger"; # Clickfinger or button-areas
        accel-speed = 0.0; # Acceleration speed (-1.0 to 1.0)
        accel-profile = "adaptive"; # adaptive or flat
        scroll-method = "two-finger"; # two-finger, edge, on-button-down, no-scroll
        scroll-button = 274; # Middle mouse button (for on-button-down)
        middle-emulation = false;
        left-handed = false;
        disabled-on-external-mouse = false;
      };

      # Mouse settings
      mouse = {
        natural-scroll = false;
        accel-speed = 0.0;
        accel-profile = "adaptive";
        scroll-method = "no-scroll";
        scroll-button = 274;
        middle-emulation = false;
        left-handed = false;
      };

      # Trackpoint settings (ThinkPad nub)
      trackpoint = {
        natural-scroll = true;
        accel-speed = 0.0;
        accel-profile = "flat";
        scroll-method = "on-button-down";
        scroll-button = 274; # Middle button
        middle-emulation = false;
      };

      # Tablet settings
      tablet = {
        map-to-output = null; # null maps to all outputs
      };

      # Focus follows mouse
      focus-follows-mouse = {
        enable = true;
        max-scroll-amount = "0.5";
      };

      # Warp mouse to focused window
      warp-mouse-to-focus = false;
    };

    # ==========================================================================
    # KEY BINDINGS
    # ==========================================================================
    # Format: { key name } = { action = "action-name"; params...; }
    keybinds = {
      # --------------------------------------------------------------------------
      # SPAWN APPLICATIONS
      # --------------------------------------------------------------------------
      "Super+Return" = {
        spawn = [ "ghostty" ];
      };
      "Super+D" = {
        spawn = noctalia "launcher toggle";
      };
      "Super+Space" = {
        spawn = noctalia "launcher toggle";
      };
      "Super+E" = {
        spawn = [ "${pkgs.kdePackages.dolphin}/bin/dolphin" ];
      };
      "Super+B" = {
        spawn = [ "zen-twilight" ];
      };
      "Super+Print" = {
        spawn = [
          "${pkgs.grim}/bin/grim"
          "-g"
          "$(${pkgs.slurp}/bin/slurp)"
          "- | ${pkgs.wl-clipboard}/bin/wl-copy"
        ];
      };
      "Super+Shift+Print" = {
        spawn = [
          "${pkgs.grim}/bin/grim"
          "- | ${pkgs.wl-clipboard}/bin/wl-copy"
        ];
      };
      "Super+Shift+E" = {
        spawn = [ "${pkgs.vscode}/bin/code" ];
      };

      # --------------------------------------------------------------------------
      # WINDOW MANAGEMENT
      # --------------------------------------------------------------------------
      # Close focused window
      "Super+Q" = {
        close-window = [ ];
      };

      # Focus windows (arrow keys)
      "Super+Left" = {
        focus-column-left = [ ];
      };
      "Super+Right" = {
        focus-column-right = [ ];
      };
      "Super+Up" = {
        focus-window-up = [ ];
      };
      "Super+Down" = {
        focus-window-down = [ ];
      };

      # Move windows (arrow keys)
      "Super+Shift+Left" = {
        move-column-left = [ ];
      };
      "Super+Shift+Right" = {
        move-column-right = [ ];
      };
      "Super+Shift+Up" = {
        move-window-up = [ ];
      };
      "Super+Shift+Down" = {
        move-window-down = [ ];
      };

      # Column width adjustment
      "Super+Comma" = {
        consume-window-into-column = [ ];
      };
      "Super+Period" = {
        expel-window-from-column = [ ];
      };
      "Super+R" = {
        switch-preset-column-width = [ ];
      };
      "Super+Shift+R" = {
        reset-window-height = [ ];
      };
      "Super+Minus" = {
        set-column-width = "-10%";
      };
      "Super+Equal" = {
        set-column-width = "+10%";
      };
      "Super+Shift+Minus" = {
        set-window-height = "-10%";
      };
      "Super+Shift+Equal" = {
        set-window-height = "+10%";
      };

      # Center focused column
      "Super+C" = {
        center-column = [ ];
      };

      # Focus and move to monitor edges
      "Super+Home" = {
        focus-column-first = [ ];
      };
      "Super+End" = {
        focus-column-last = [ ];
      };
      "Super+Shift+Home" = {
        move-column-to-first = [ ];
      };
      "Super+Shift+End" = {
        move-column-to-last = [ ];
      };

      # --------------------------------------------------------------------------
      # WORKSPACE MANAGEMENT
      # --------------------------------------------------------------------------
      # Switch to workspace 1-10
      "Super+1" = {
        focus-workspace = 1;
      };
      "Super+2" = {
        focus-workspace = 2;
      };
      "Super+3" = {
        focus-workspace = 3;
      };
      "Super+4" = {
        focus-workspace = 4;
      };
      "Super+5" = {
        focus-workspace = 5;
      };
      "Super+6" = {
        focus-workspace = 6;
      };
      "Super+7" = {
        focus-workspace = 7;
      };
      "Super+8" = {
        focus-workspace = 8;
      };
      "Super+9" = {
        focus-workspace = 9;
      };
      "Super+0" = {
        focus-workspace = 10;
      };

      # Move window to workspace 1-10
      "Super+Shift+1" = {
        move-column-to-workspace = 1;
      };
      "Super+Shift+2" = {
        move-column-to-workspace = 2;
      };
      "Super+Shift+3" = {
        move-column-to-workspace = 3;
      };
      "Super+Shift+4" = {
        move-column-to-workspace = 4;
      };
      "Super+Shift+5" = {
        move-column-to-workspace = 5;
      };
      "Super+Shift+6" = {
        move-column-to-workspace = 6;
      };
      "Super+Shift+7" = {
        move-column-to-workspace = 7;
      };
      "Super+Shift+8" = {
        move-column-to-workspace = 8;
      };
      "Super+Shift+9" = {
        move-column-to-workspace = 9;
      };
      "Super+Shift+0" = {
        move-column-to-workspace = 10;
      };

      # Workspace navigation
      "Super+Page_Down" = {
        focus-workspace-down = [ ];
      };
      "Super+Page_Up" = {
        focus-workspace-up = [ ];
      };
      "Super+Shift+Page_Down" = {
        move-column-to-workspace-down = [ ];
      };
      "Super+Shift+Page_Up" = {
        move-column-to-workspace-up = [ ];
      };
      "Super+BracketLeft" = {
        focus-workspace-down = [ ];
      }; # Alt-Tab style
      "Super+BracketRight" = {
        focus-workspace-up = [ ];
      };

      # --------------------------------------------------------------------------
      # MONITOR/OUTPUT MANAGEMENT
      # --------------------------------------------------------------------------
      # Focus monitor
      "Super+Ctrl+Left" = {
        focus-monitor-left = [ ];
      };
      "Super+Ctrl+Right" = {
        focus-monitor-right = [ ];
      };
      "Super+Ctrl+Up" = {
        focus-monitor-up = [ ];
      };
      "Super+Ctrl+Down" = {
        focus-monitor-down = [ ];
      };

      # Move window to monitor
      "Super+Ctrl+Shift+Left" = {
        move-column-to-monitor-left = [ ];
      };
      "Super+Ctrl+Shift+Right" = {
        move-column-to-monitor-right = [ ];
      };
      "Super+Ctrl+Shift+Up" = {
        move-column-to-monitor-up = [ ];
      };
      "Super+Ctrl+Shift+Down" = {
        move-column-to-monitor-down = [ ];
      };

      # --------------------------------------------------------------------------
      # WINDOW STATE
      # --------------------------------------------------------------------------
      # Toggle fullscreen
      "Super+F" = {
        fullscreen-window = [ ];
      };
      "Super+Shift+F" = {
        toggle-windowed-fullscreen = [ ];
      };

      # Toggle floating
      "Super+V" = {
        toggle-window-floating = [ ];
      };
      "Super+Shift+V" = {
        switch-focus-between-floating-and-tiling = [ ];
      };

      # Pin window (show on all workspaces)
      "Super+P" = {
        toggle-window-rule = "floating";
      };

      # --------------------------------------------------------------------------
      # LAYOUT ACTIONS
      # --------------------------------------------------------------------------
      # Switch layout (scrollable-tiling only)
      "Super+Tab" = {
        focus-workspace-down = [ ];
      };
      "Super+Shift+Tab" = {
        focus-workspace-up = [ ];
      };

      # --------------------------------------------------------------------------
      # CLIPBOARD
      # --------------------------------------------------------------------------
      "Super+Shift+V" = {
        spawn = noctalia "launcher toggle";
      };

      # --------------------------------------------------------------------------
      # MEDIA CONTROLS
      # --------------------------------------------------------------------------
      "XF86AudioRaiseVolume" = {
        spawn = noctalia "volume increase";
      };
      "XF86AudioLowerVolume" = {
        spawn = noctalia "volume decrease";
      };
      "XF86AudioMute" = {
        spawn = noctalia "volume muteOutput";
      };
      "XF86AudioMicMute" = {
        spawn = noctalia "volume muteInput";
      };
      "XF86MonBrightnessUp" = {
        spawn = noctalia "brightness increase";
      };
      "XF86MonBrightnessDown" = {
        spawn = noctalia "brightness decrease";
      };
      "XF86AudioPlay" = {
        spawn = noctalia "media playPause";
      };
      "XF86AudioNext" = {
        spawn = noctalia "media next";
      };
      "XF86AudioPrev" = {
        spawn = noctalia "media previous";
      };
      "XF86AudioStop" = {
        spawn = noctalia "media stop";
      };

      # --------------------------------------------------------------------------
      # SYSTEM ACTIONS
      # --------------------------------------------------------------------------
      # Quit niri (logout)
      "Super+Shift+Escape" = {
        quit = [ ];
      };

      # Lock screen
      "Super+Escape" = {
        spawn = [ "${pkgs.swaylock}/bin/swaylock" ];
      };

      # Power menu (noctalia session menu)
      "Super+Shift+P" = {
        spawn = noctalia "sessionMenu toggle";
      };

      # Suspend
      "Super+Ctrl+Escape" = {
        spawn = [
          "systemctl"
          "suspend"
        ];
      };

      # --------------------------------------------------------------------------
      # NIRI ACTIONS
      # --------------------------------------------------------------------------
      # Toggle keyboard focus
      "Super+Ctrl+Space" = {
        toggle-keyboard-focus = [ ];
      };

      # Debug toggle
      "Super+Shift+D" = {
        toggle-debug-tint = [ ];
      };

      # Reload config
      "Super+Shift+C" = {
        load-config-file = [ ];
      };

      # Show hotkey overlay
      "Super+Slash" = {
        show-hotkey-overlay = [ ];
      };
    };

    # ==========================================================================
    # WINDOW RULES
    # ==========================================================================
    # Apply specific behaviors to windows matching criteria
    window-rules = [
      # Float specific applications
      {
        matches = [
          { app-id = "pavucontrol"; }
          { app-id = "nm-connection-editor"; }
          { app-id = "blueman-manager"; }
          { app-id = "gnome-calculator"; }
          { app-id = "gnome-control-center"; }
          { app-id = "file-roller"; }
          { title = "File Transfer*"; }
          { title = "Copy*"; }
          { title = "Passwords*"; }
          { app-id = "pinentry-"; }
        ];
        open-floating = true;
      }

      # Picture-in-Picture windows
      {
        matches = [ { title = "Picture-in-Picture"; } ];
        open-floating = true;
        default-floating-position = {
          x = 0;
          y = 0;
        };
        default-column-width = {
          fixed = 400;
        };
        default-window-height = {
          fixed = 225;
        };
      }

      # Full-width applications
      {
        matches = [
          { app-id = "firefox"; }
          { app-id = "zen-twilight"; }
          { app-id = "librewolf"; }
          { app-id = "chromium"; }
          { app-id = "brave"; }
        ];
        default-column-width = {
          proportion = 1.0;
        };
      }

      # Terminal default width
      {
        matches = [
          { app-id = "Alacritty"; }
          { app-id = "kitty"; }
          { app-id = "foot"; }
          { app-id = "gnome-terminal"; }
          { app-id = "com.mitchellh.ghostty"; }
        ];
        default-column-width = {
          proportion = 0.5;
        };
      }

      # IDEs and editors
      {
        matches = [
          { app-id = "code"; }
          { app-id = "code-url-handler"; }
          { app-id = "jetbrains-"; }
          { app-id = "emacs"; }
        ];
        default-column-width = {
          proportion = 0.7;
        };
      }

      # Games (usually want floating or fullscreen)
      {
        matches = [
          { app-id = "steam"; }
          { app-id = "lutris"; }
          { app-id = "heroic"; }
          { app-id = "minecraft"; }
          { app-id = "prism-launcher"; }
        ];
        open-floating = true;
      }

      # Screen sharing prompts (always float)
      {
        matches = [ { title = "Choose what to share"; } ];
        open-floating = true;
        focus-ring.enable = false;
        border.enable = false;
      }

      # Block screen-sharing of sensitive windows
      {
        matches = [
          { app-id = "bitwarden"; }
          { app-id = "keepassxc"; }
          { app-id = "1password"; }
          { title = "*Password*"; }
          { title = "*Secret*"; }
        ];
        block-out-from = "screen-capture";
      }
    ];

    # ==========================================================================
    # LAYER RULES
    # ==========================================================================
    # Configure behavior of layer-shell surfaces (notifications, panels, etc.)
    layer-rules = [
      # Noctalia shell (bar, notifications, launcher, dock)
      {
        matches = [ { namespace = "noctalia"; } ];
        place-within-backdrop = false;
      }

      # Quickshell (noctalia-qs underlying engine)
      {
        matches = [ { namespace = "quickshell"; } ];
        place-within-backdrop = false;
      }

      # GTK layer shell apps (polkit dialogs, etc.)
      {
        matches = [ { namespace = "gtk-layer-shell"; } ];
        place-within-backdrop = false;
      }

      # Screen lock (above everything)
      {
        matches = [ { namespace = "swaylock"; } ];
        place-within-backdrop = true;
      }
    ];

    # ==========================================================================
    # WORKSPACES
    # ==========================================================================
    # Named workspaces for organization (optional)
    # Format: workspace "name" { output = "monitor-name"; }
    # Example:
    # workspaces = {
    #   "1-web" = { };
    #   "2-code" = { };
    #   "3-term" = { };
    #   "4-media" = { };
    #   "5-gaming" = { };
    # };
  }; # mkIf
}
