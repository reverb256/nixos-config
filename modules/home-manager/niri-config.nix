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
}:
let
  inherit (lib) mkDefault mkIf;
  # Check if niri home-manager module is loaded (provides lib.niri.actions)
  niriHmAvailable = config.lib ? niri;
in
{
  # Only configure niri settings when the HM module is actually available
  programs.niri.settings = mkIf niriHmAvailable (
    let
      acts = config.lib.niri.actions;
    in
    {
      # ==========================================================================
      # GENERAL SETTINGS
      # ==========================================================================
      spawn-at-startup = [
        { argv = [ "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1" ]; }
        # Noctalia desktop shell (replaces waybar, mako, fuzzel, swww)
        # GST_PLUGIN_PATH must be set inline because niri spawn-at-startup
        # inherits env before uwsm sources env-niri, causing missing fakesink
        {
          argv = [
            "${pkgs.bash}/bin/bash"
            "-c"
            "export GST_PLUGIN_PATH=${
              lib.makeSearchPathOutput "lib/gstreamer-1.0" "lib/gstreamer-1.0" [
                pkgs.gst_all_1.gstreamer
                pkgs.gst_all_1.gst-plugins-base
                pkgs.gst_all_1.gst-plugins-bad
                pkgs.gst_all_1.gst-plugins-good
              ]
            } && exec noctalia-shell"
          ];
        }
        { sh = "wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store"; }
        { sh = "wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store"; }
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
          active = {
            color = "#7aa2f7";
          }; # Tokyo Night blue
          inactive = {
            color = "#3b4261";
          }; # Tokyo Night comment
        };

        border = {
          enable = false;
          width = 1;
          active = {
            color = "#7aa2f7";
          };
          inactive = {
            color = "#3b4261";
          };
        };

        # Default column width for new windows (50% of screen)
        default-column-width = {
          proportion = 0.5;
        };

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

        # HDMI-A-2: Samsung 4K HDR TV (isolated — positioned far right, no mouse reach)
        "HDMI-A-2" = {
          mode = {
            width = 3840;
            height = 2160;
            refresh = 60.0;
          };
          position = {
            x = 10000;
            y = 0;
          };
          scale = 1.5;
        };
      };

      # ==========================================================================
      # NAMED WORKSPACES (bound to specific monitors)
      # 1-4: ZOWIE (DP-5) | 5-6: ASUS (DP-4) | 7-8: Acer (DP-6) | 9-10: Samsung (HDMI-A-2)
      # ==========================================================================
      workspaces = {
        "zowie-1" = { open-on-output = "DP-5"; };
        "zowie-2" = { open-on-output = "DP-5"; };
        "zowie-3" = { open-on-output = "DP-5"; };
        "zowie-4" = { open-on-output = "DP-5"; };
        "asus-1" = { open-on-output = "DP-4"; };
        "asus-2" = { open-on-output = "DP-4"; };
        "acer-1" = { open-on-output = "DP-6"; };
        "acer-2" = { open-on-output = "DP-6"; };
        "samsung-1" = { open-on-output = "HDMI-A-2"; };
        "samsung-2" = { open-on-output = "HDMI-A-2"; };
        "scratch" = { open-on-output = "DP-5"; }; # Scratchpad workspace (Mod+S)
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
      # Omarchy-inspired layout with full Noctalia shell integration
      # ==========================================================================
      binds = with acts; {
        # =========================================================================
        # APPLICATIONS (Omarchy-style: Mod+Letter = app)
        # Terminal: always spawn new (no launch-or-focus)
        # Other apps: launch-or-focus to prevent duplicates
        # =========================================================================
        "Mod+Return".action = spawn "ghostty"; # Always spawn new terminal
        "Mod+Shift+Return".action = spawn "zen-twilight"; # Always spawn new browser
        "Mod+B".action = spawn "launch-or-focus" "Zen" "zen-twilight";
        "Mod+Shift+B".action = spawn "zen-twilight" "--private-window";
        "Mod+E".action = spawn "launch-or-focus" "Dolphin" "${pkgs.kdePackages.dolphin}/bin/dolphin";
        "Mod+N".action = spawn "launch-or-focus" "KWrite" "${pkgs.kdePackages.kwrite}/bin/kwrite";
        "Mod+Shift+N".action = spawn "launch-or-focus" "Kate" "${pkgs.kdePackages.kate}/bin/kate";
        "Mod+O".action = spawn "launch-or-focus" "Obsidian" "obsidian";
        "Mod+T".action = spawn "ghostty" "-e" "btop";
        "Mod+D".action = spawn "ghostty" "-e" "lazydocker";
        "Mod+G".action = spawn "launch-or-focus" "Vesktop" "vesktop";
        "Mod+Shift+G".action = spawn "zen-twilight" "--new-window" "https://grok.com";
        "Mod+A".action = spawn "launch-or-focus" "LM" "lm-studio";
        "Mod+Shift+A".action = spawn "zen-twilight" "--new-window" "https://chatgpt.com";
        "Mod+M".action = spawn "launch-or-focus" "Spotify" "flatpak" "run" "com.spotify.Client";
        "Mod+Slash".action = spawn "launch-or-focus" "Bitwarden" "flatpak" "run" "com.bitwarden.desktop";
        "Mod+K".action = show-hotkey-overlay;

        # =========================================================================
        # NOCTALIA SHELL — Launcher modes
        # All modes use the same launcher with different search prefixes
        # =========================================================================
        "Mod+Space".action = spawn "noctalia-shell" "ipc" "call" "launcher toggle";
        "Mod+Ctrl+V".action = spawn "noctalia-shell" "ipc" "call" "launcher clipboard";
        "Mod+Ctrl+E".action = spawn "noctalia-shell" "ipc" "call" "launcher emoji";
        "Mod+Ctrl+Slash".action = spawn "noctalia-shell" "ipc" "call" "launcher command";
        "Mod+Shift+Slash".action = spawn "noctalia-shell" "ipc" "call" "launcher windows";

        # =========================================================================
        # NOCTALIA SHELL — Panels & toggles
        # =========================================================================
        "Mod+S".action = spawn "scratchpad-toggle"; # Scratchpad workspace
        "Mod+Comma".action = spawn "noctalia-shell" "ipc" "call" "notifications dismissLast";
        "Mod+Alt+Space".action = spawn "noctalia-shell" "ipc" "call" "settings toggle"; # Settings panel
        "Mod+Shift+Space".action = spawn "noctalia-shell" "ipc" "call" "bar toggle";
        "Mod+Ctrl+A".action = spawn "noctalia-shell" "ipc" "call" "volume togglePanel";
        "Mod+Ctrl+W".action = spawn "noctalia-shell" "ipc" "call" "network togglePanel";
        "Mod+Ctrl+B".action = spawn "noctalia-shell" "ipc" "call" "bluetooth togglePanel";
        "Mod+Ctrl+I".action = spawn "noctalia-shell" "ipc" "call" "idleInhibitor toggle";
        "Mod+Ctrl+N".action = spawn "noctalia-shell" "ipc" "call" "nightLight toggle";
        "Mod+Ctrl+D".action = spawn "noctalia-shell" "ipc" "call" "darkMode toggle";
        "Mod+Ctrl+T".action = spawn "noctalia-shell" "ipc" "call" "systemMonitor toggle";
        "Mod+Ctrl+S".action = spawn "noctalia-shell" "ipc" "call" "share toggle"; # Share (LocalSend)
        "Mod+Ctrl+L".action = spawn "noctalia-shell" "ipc" "call" "lockScreen lock"; # Quick lock
        "Mod+Ctrl+O".action = spawn "noctalia-shell" "ipc" "call" "controlCenter toggle"; # Control center (moved from Mod+S)
        "Mod+Ctrl+Shift+W".action = spawn "noctalia-shell" "ipc" "call" "wallpaper random";

        # =========================================================================
        # NOTIFICATIONS (Omarchy hierarchy: Mod+Comma = dismiss, variants for more)
        # =========================================================================
        "Mod+Shift+Comma".action = spawn "noctalia-shell" "ipc" "call" "notifications dismissAll";
        "Mod+Ctrl+Comma".action = spawn "noctalia-shell" "ipc" "call" "notifications toggleDND";
        "Mod+Alt+Comma".action = spawn "noctalia-shell" "ipc" "call" "notifications toggleHistory";
        "Mod+Alt+Shift+Comma".action = spawn "noctalia-shell" "ipc" "call" "notifications invokeDefault";

        # =========================================================================
        # SCREENSHOTS & CAPTURE
        # grim+slurp for region/fullscreen → clipboard
        # niri built-in for screen/window capture UI
        # =========================================================================
        "Print".action = spawn-sh ''FILE="$HOME/Pictures/Screenshots/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png" && mkdir -p "$(dirname "$FILE")" && ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "$FILE" && ${pkgs.wl-clipboard}/bin/wl-copy < "$FILE" && ${pkgs.satty}/bin/satty --filename "$FILE" --output-filename "$FILE" --actions-on-enter save-to-clipboard --save-after-copy --copy-command 'wl-copy' &'';
        "Mod+Print".action = spawn "niri" "msg" "action" "pick-color"; # Color picker
        "Mod+Shift+Print".action = spawn-sh "${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy";
        "Mod+Alt+Print".action = spawn "niri" "msg" "action" "screenshot-window";
        "Mod+Ctrl+Shift+Print".action = spawn "niri" "msg" "action" "screenshot-screen";
        "Alt+Print".action = spawn "wf-recorder"; # Screen recording toggle

        # =========================================================================
        # WINDOW MANAGEMENT (arrow-only, no hjkl)
        # =========================================================================
        "Mod+Q".action = close-window;
        "Alt+Tab".action = focus-window-previous;
        "Mod+Left".action = focus-column-left;
        "Mod+Right".action = focus-column-right;
        "Mod+Up".action = focus-window-up;
        "Mod+Down".action = focus-window-down;
        "Mod+Shift+Left".action = move-column-left;
        "Mod+Shift+Right".action = move-column-right;
        "Mod+Shift+Up".action = move-window-up;
        "Mod+Shift+Down".action = move-window-down;
        "Mod+Period".action = consume-window-into-column;
        "Mod+Ctrl+Period".action = expel-window-from-column;
        "Mod+R".action = switch-preset-column-width;
        "Mod+Shift+R".action = reset-window-height;
        "Mod+Minus".action = set-column-width "-10%";
        "Mod+Equal".action = set-column-width "+10%";
        "Mod+Shift+Minus".action = set-window-height "-10%";
        "Mod+Shift+Equal".action = set-window-height "+10%";
        "Mod+C".action = center-column;
        "Mod+Home".action = focus-column-first;
        "Mod+End".action = focus-column-last;
        "Mod+Shift+Home".action = move-column-to-first;
        "Mod+Shift+End".action = move-column-to-last;

        # =========================================================================
        # WINDOW STATE
        # =========================================================================
        "Mod+F".action = fullscreen-window;
        "Mod+Shift+F".action = maximize-column;
        "Mod+V".action = toggle-window-floating;
        "Mod+Shift+V".action = switch-focus-between-floating-and-tiling;

        # =========================================================================
        # WORKSPACES (named, bound to specific monitors)
        # 1-4: ZOWIE (DP-5) | 5-6: ASUS (DP-4) | 7-8: Acer (DP-6) | 9-10: Samsung (HDMI-A-2)
        # =========================================================================
        "Mod+1".action = focus-workspace "zowie-1";
        "Mod+2".action = focus-workspace "zowie-2";
        "Mod+3".action = focus-workspace "zowie-3";
        "Mod+4".action = focus-workspace "zowie-4";
        "Mod+5".action = focus-workspace "asus-1";
        "Mod+6".action = focus-workspace "asus-2";
        "Mod+7".action = focus-workspace "acer-1";
        "Mod+8".action = focus-workspace "acer-2";
        "Mod+9".action = focus-workspace "samsung-1";
        "Mod+0".action = focus-workspace "samsung-2";
        "Mod+Shift+1".action.move-window-to-workspace = "zowie-1";
        "Mod+Shift+2".action.move-window-to-workspace = "zowie-2";
        "Mod+Shift+3".action.move-window-to-workspace = "zowie-3";
        "Mod+Shift+4".action.move-window-to-workspace = "zowie-4";
        "Mod+Shift+5".action.move-window-to-workspace = "asus-1";
        "Mod+Shift+6".action.move-window-to-workspace = "asus-2";
        "Mod+Shift+7".action.move-window-to-workspace = "acer-1";
        "Mod+Shift+8".action.move-window-to-workspace = "acer-2";
        "Mod+Shift+9".action.move-window-to-workspace = "samsung-1";
        "Mod+Shift+0".action.move-window-to-workspace = "samsung-2";
        "Mod+Page_Down".action = focus-workspace-down;
        "Mod+Page_Up".action = focus-workspace-up;
        "Mod+Shift+Page_Down".action = move-column-to-workspace-down;
        "Mod+Shift+Page_Up".action = move-column-to-workspace-up;
        "Mod+Tab".action = focus-workspace-down;
        "Mod+Shift+Tab".action = focus-workspace-up;
        "Mod+Ctrl+Tab".action = focus-workspace-previous;

        # =========================================================================
        # SCRATCHPAD (workspace toggle via script)
        # =========================================================================

        # =========================================================================
        # MONITOR/OUTPUT MANAGEMENT
        # Focus monitor / move column / move entire workspace
        # =========================================================================
        "Mod+Ctrl+Left".action = focus-monitor-left;
        "Mod+Ctrl+Right".action = focus-monitor-right;
        "Mod+Ctrl+Up".action = focus-monitor-up;
        "Mod+Ctrl+Down".action = focus-monitor-down;
        "Mod+Ctrl+Shift+Left".action = move-column-to-monitor-left;
        "Mod+Ctrl+Shift+Right".action = move-column-to-monitor-right;
        "Mod+Ctrl+Shift+Up".action = move-column-to-monitor-up;
        "Mod+Ctrl+Shift+Down".action = move-column-to-monitor-down;
        "Mod+Shift+Alt+Left".action = move-workspace-to-monitor-left;
        "Mod+Shift+Alt+Right".action = move-workspace-to-monitor-right;
        "Mod+Shift+Alt+Up".action = move-workspace-to-monitor-up;
        "Mod+Shift+Alt+Down".action = move-workspace-to-monitor-down;

        # =========================================================================
        # MEDIA KEYS (Noctalia IPC — gives OSD, panel sync, bar updates)
        # =========================================================================
        "XF86AudioRaiseVolume".action = spawn "noctalia-shell" "ipc" "call" "volume increase";
        "XF86AudioLowerVolume".action = spawn "noctalia-shell" "ipc" "call" "volume decrease";
        "XF86AudioMute".action = spawn "noctalia-shell" "ipc" "call" "volume muteOutput";
        "XF86AudioMicMute".action = spawn "noctalia-shell" "ipc" "call" "volume muteInput";
        "XF86MonBrightnessUp".action = spawn "brightness-all" "up";
        "XF86MonBrightnessDown".action = spawn "brightness-all" "down";
        "XF86AudioPlay".action = spawn "noctalia-shell" "ipc" "call" "media playPause";
        "XF86AudioNext".action = spawn "noctalia-shell" "ipc" "call" "media next";
        "XF86AudioPrev".action = spawn "noctalia-shell" "ipc" "call" "media previous";
        "XF86AudioStop".action = spawn "noctalia-shell" "ipc" "call" "media stop";

        # =========================================================================
        # SYSTEM
        # =========================================================================
        "Mod+Escape".action = spawn "noctalia-shell" "ipc" "call" "sessionMenu toggle"; # System menu (lock/suspend/reboot/shutdown)
        "Mod+Ctrl+Escape".action = spawn "systemctl" "suspend";
        "Mod+Shift+Escape".action = quit;
        "Mod+Shift+C".action = spawn "niri" "msg" "action" "load-config-file";
        "Ctrl+Alt+Delete".action = spawn-sh ''for wid in $(niri msg windows 2>/dev/null | grep -oP 'Window ID \\K[0-9]+'); do niri msg action close-window --id "$wid"; done''; # Close all windows
      };

      # ==========================================================================
      # WINDOW RULES
      # ==========================================================================
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
            { title = "Passwords.*"; }
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
            relative-to = "top-left";
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

        # Screen sharing prompts (always float, no border)
        {
          matches = [ { title = "Choose what to share"; } ];
          open-floating = true;
        }

        # Block screen-sharing of sensitive windows
        {
          matches = [
            { app-id = "bitwarden"; }
            { app-id = "keepassxc"; }
            { app-id = "1password"; }
            { title = ".*Password.*"; }
            { title = ".*Secret.*"; }
          ];
          block-out-from = "screen-capture";
        }

        # Genshin Impact — always fullscreen on TV (migrated from kwinrulesrc)
        {
          matches = [ { app-id = ".*GenshinImpact.*"; } ];
          open-on-output = "HDMI-A-2";
          open-fullscreen = true;
        }
      ];

      # ==========================================================================
      # LAYER RULES
      # ==========================================================================
      layer-rules = [
        # Noctalia desktop shell (bar, panels, notifications)
        {
          matches = [ { namespace = "noctalia.*"; } ];
          place-within-backdrop = false;
        }

        # Quickshell layer shell (noctalia backend)
        {
          matches = [ { namespace = "quickshell.*"; } ];
          place-within-backdrop = false;
        }

        # GTK layer shell apps
        {
          matches = [ { namespace = "gtk-layer-shell"; } ];
          place-within-backdrop = false;
        }
      ];
    }
  );
}
