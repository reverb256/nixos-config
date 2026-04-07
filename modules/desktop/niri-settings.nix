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
  programs.niri.settings = {
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
      "${mod}+Return" = {
        spawn = [ "${pkgs.kdePackages.konsole}/bin/konsole" ];
      };
      "${mod}+D" = {
        spawn = noctalia "launcher toggle";
      };
      "${mod}+Space" = {
        spawn = noctalia "launcher toggle";
      };
      "${mod}+E" = {
        spawn = [ "${pkgs.dolphin}/bin/dolphin" ];
      };
      "${mod}+B" = {
        spawn = [ "${pkgs.firefox}/bin/firefox" ];
      };
      "${mod}+Print" = {
        spawn = [
          "${pkgs.grim}/bin/grim"
          "-g"
          "$(${pkgs.slurp}/bin/slurp)"
          "- | ${pkgs.wl-clipboard}/bin/wl-copy"
        ];
      };
      "${mod}+Shift+Print" = {
        spawn = [
          "${pkgs.grim}/bin/grim"
          "- | ${pkgs.wl-clipboard}/bin/wl-copy"
        ];
      };
      "${mod}+Shift+E" = {
        spawn = [ "${pkgs.code}/bin/code" ];
      };

      # --------------------------------------------------------------------------
      # WINDOW MANAGEMENT
      # --------------------------------------------------------------------------
      # Close focused window
      "${mod}+Q" = {
        close-window = [ ];
      };

      # Focus windows (arrow keys)
      "${mod}+Left" = {
        focus-column-left = [ ];
      };
      "${mod}+Right" = {
        focus-column-right = [ ];
      };
      "${mod}+Up" = {
        focus-window-up = [ ];
      };
      "${mod}+Down" = {
        focus-window-down = [ ];
      };

      # Move windows (arrow keys)
      "${mod}+Shift+Left" = {
        move-column-left = [ ];
      };
      "${mod}+Shift+Right" = {
        move-column-right = [ ];
      };
      "${mod}+Shift+Up" = {
        move-window-up = [ ];
      };
      "${mod}+Shift+Down" = {
        move-window-down = [ ];
      };

      # Column width adjustment
      "${mod}+Comma" = {
        consume-window-into-column = [ ];
      };
      "${mod}+Period" = {
        expel-window-from-column = [ ];
      };
      "${mod}+R" = {
        switch-preset-column-width = [ ];
      };
      "${mod}+Shift+R" = {
        reset-window-height = [ ];
      };
      "${mod}+Minus" = {
        set-column-width = "-10%";
      };
      "${mod}+Equal" = {
        set-column-width = "+10%";
      };
      "${mod}+Shift+Minus" = {
        set-window-height = "-10%";
      };
      "${mod}+Shift+Equal" = {
        set-window-height = "+10%";
      };

      # Center focused column
      "${mod}+C" = {
        center-column = [ ];
      };

      # Focus and move to monitor edges
      "${mod}+Home" = {
        focus-column-first = [ ];
      };
      "${mod}+End" = {
        focus-column-last = [ ];
      };
      "${mod}+Shift+Home" = {
        move-column-to-first = [ ];
      };
      "${mod}+Shift+End" = {
        move-column-to-last = [ ];
      };

      # --------------------------------------------------------------------------
      # WORKSPACE MANAGEMENT
      # --------------------------------------------------------------------------
      # Switch to workspace 1-10
      "${mod}+1" = {
        focus-workspace = 1;
      };
      "${mod}+2" = {
        focus-workspace = 2;
      };
      "${mod}+3" = {
        focus-workspace = 3;
      };
      "${mod}+4" = {
        focus-workspace = 4;
      };
      "${mod}+5" = {
        focus-workspace = 5;
      };
      "${mod}+6" = {
        focus-workspace = 6;
      };
      "${mod}+7" = {
        focus-workspace = 7;
      };
      "${mod}+8" = {
        focus-workspace = 8;
      };
      "${mod}+9" = {
        focus-workspace = 9;
      };
      "${mod}+0" = {
        focus-workspace = 10;
      };

      # Move window to workspace 1-10
      "${mod}+Shift+1" = {
        move-column-to-workspace = 1;
      };
      "${mod}+Shift+2" = {
        move-column-to-workspace = 2;
      };
      "${mod}+Shift+3" = {
        move-column-to-workspace = 3;
      };
      "${mod}+Shift+4" = {
        move-column-to-workspace = 4;
      };
      "${mod}+Shift+5" = {
        move-column-to-workspace = 5;
      };
      "${mod}+Shift+6" = {
        move-column-to-workspace = 6;
      };
      "${mod}+Shift+7" = {
        move-column-to-workspace = 7;
      };
      "${mod}+Shift+8" = {
        move-column-to-workspace = 8;
      };
      "${mod}+Shift+9" = {
        move-column-to-workspace = 9;
      };
      "${mod}+Shift+0" = {
        move-column-to-workspace = 10;
      };

      # Workspace navigation
      "${mod}+Page_Down" = {
        focus-workspace-down = [ ];
      };
      "${mod}+Page_Up" = {
        focus-workspace-up = [ ];
      };
      "${mod}+Shift+Page_Down" = {
        move-column-to-workspace-down = [ ];
      };
      "${mod}+Shift+Page_Up" = {
        move-column-to-workspace-up = [ ];
      };
      "${mod}+BracketLeft" = {
        focus-workspace-down = [ ];
      }; # Alt-Tab style
      "${mod}+BracketRight" = {
        focus-workspace-up = [ ];
      };

      # --------------------------------------------------------------------------
      # MONITOR/OUTPUT MANAGEMENT
      # --------------------------------------------------------------------------
      # Focus monitor
      "${mod}+Ctrl+Left" = {
        focus-monitor-left = [ ];
      };
      "${mod}+Ctrl+Right" = {
        focus-monitor-right = [ ];
      };
      "${mod}+Ctrl+Up" = {
        focus-monitor-up = [ ];
      };
      "${mod}+Ctrl+Down" = {
        focus-monitor-down = [ ];
      };

      # Move window to monitor
      "${mod}+Ctrl+Shift+Left" = {
        move-column-to-monitor-left = [ ];
      };
      "${mod}+Ctrl+Shift+Right" = {
        move-column-to-monitor-right = [ ];
      };
      "${mod}+Ctrl+Shift+Up" = {
        move-column-to-monitor-up = [ ];
      };
      "${mod}+Ctrl+Shift+Down" = {
        move-column-to-monitor-down = [ ];
      };

      # --------------------------------------------------------------------------
      # WINDOW STATE
      # --------------------------------------------------------------------------
      # Toggle fullscreen
      "${mod}+F" = {
        fullscreen-window = [ ];
      };
      "${mod}+Shift+F" = {
        toggle-windowed-fullscreen = [ ];
      };

      # Toggle floating
      "${mod}+V" = {
        toggle-window-floating = [ ];
      };
      "${mod}+Shift+V" = {
        switch-focus-between-floating-and-tiling = [ ];
      };

      # Pin window (show on all workspaces)
      "${mod}+P" = {
        toggle-window-rule = "floating";
      };

      # --------------------------------------------------------------------------
      # LAYOUT ACTIONS
      # --------------------------------------------------------------------------
      # Switch layout (scrollable-tiling only)
      "${mod}+Tab" = {
        focus-workspace-down = [ ];
      };
      "${mod}+Shift+Tab" = {
        focus-workspace-up = [ ];
      };

      # --------------------------------------------------------------------------
      # CLIPBOARD
      # --------------------------------------------------------------------------
      "${mod}+Shift+V" = {
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
      "${mod}+Shift+Escape" = {
        quit = [ ];
      };

      # Lock screen
      "${mod}+Escape" = {
        spawn = [ "${pkgs.swaylock}/bin/swaylock" ];
      };

      # Power menu (noctalia session menu)
      "${mod}+Shift+P" = {
        spawn = noctalia "sessionMenu toggle";
      };

      # Suspend
      "${mod}+Ctrl+Escape" = {
        spawn = [
          "systemctl"
          "suspend"
        ];
      };

      # --------------------------------------------------------------------------
      # NIRI ACTIONS
      # --------------------------------------------------------------------------
      # Toggle keyboard focus
      "${mod}+Ctrl+Space" = {
        toggle-keyboard-focus = [ ];
      };

      # Debug toggle
      "${mod}+Shift+D" = {
        toggle-debug-tint = [ ];
      };

      # Reload config (if supported)
      "${mod}+Shift+C" = {
        reload-config = [ ];
      };

      # Show hotkey overlay
      "${mod}+Slash" = {
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
          { app-id = "konsole"; }
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
    # NVIDIA DEBUG OPTIONS
    # ==========================================================================
    # These are critical for multi-GPU NVIDIA setups with VT switching:
    #   - render-drm-device: force niri to render on the 3090 (card2)
    #     which has all 4 monitors connected
    #   - ignore-drm-device: ignore the 3060 Ti (card1) which has no
    #     connected displays, prevents DRM auth errors on VT switch
    #   - force-disable-connectors-on-resume: after a VT switch back to
    #     niri, disable and re-enable all connectors to clear stale state
    #     left by the previous compositor (fixes frozen/corrupted displays)
    debug = {
      render-drm-device = "/dev/dri/card2";
      ignore-drm-device = "/dev/dri/card1";
      force-disable-connectors-on-resume = true;
    };

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
  };
}
