{
  config,
  lib,
  pkgs,
  inputs,
  hostName,
  ...
}: let
  inherit (lib) mkDefault mkIf;
  niriHmAvailable = config.lib ? niri;
in {
  programs.niri.settings = mkIf niriHmAvailable (lib.mkMerge [
    (
      let
        acts =
          if niriHmAvailable
          then config.lib.niri.actions
          else {};
      in {
        spawn-at-startup = [
          {
            argv = [
              "uwsm"
              "finalize"
            ];
          }
          {
            argv = [
              "uwsm"
              "app"
              "-s"
              "s"
              "--"
              "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
            ];
          }
          # 2026-07-07: noctalia daemon moved out of spawn-at-startup.
          # Transient uwsm-app units intentionally do NOT restart on
          # failure — when the cat pressed sleep and the daemon died,
          # nothing brought it back. Spawn ckb-next still inline.
          {
            argv = [
              "uwsm"
              "app"
              "-s"
              "b"
              "--"
              "ckb-next"
              "-b"
            ];
          }
          # Clipboard monitoring moved to CopyQ (home-manager module)
        ];

        cursor = {
          theme = lib.mkForce "Adwaita";
          size = mkDefault 24;
          hide-on-key-press = true;
          hide-after-inactive-ms = 3000;
        };

        hotkey-overlay = {
          skip-at-startup = false;
          hide-not-bound = true;
        };

        prefer-no-csd = true;

        layout = {
          focus-ring = {
            enable = true;
            width = 2;
            active = {
              color = "#7aa2f7";
            };
            inactive = {
              color = "#3b4261";
            };
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
          default-column-width = {
            proportion = 0.5;
          };
          center-focused-column = "never";
          gaps = 8;
        };

        outputs = {
          "*" = {
            scale = 1.0;
          };
        };

        input = {
          keyboard = {
            xkb = {
              layout = "us";
              variant = "";
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

        binds = with acts; {
          "Mod+Return".action = spawn "uwsm" "app" "--" "alacritty";
          "Mod+B".action = spawn "launch-or-focus" "Zen" "uwsm" "app" "--" "zen-twilight";
          "Mod+Shift+B".action = spawn "uwsm" "app" "--" "zen-twilight" "--private-window";
          "Mod+E".action = spawn "launch-or-focus" "Dolphin" "${pkgs.kdePackages.dolphin}/bin/dolphin";
          "Mod+N".action =
            spawn "launch-or-focus" "KWrite" "uwsm" "app" "--"
            "${pkgs.kdePackages.kate}/bin/kwrite";
          "Mod+Shift+N".action =
            spawn "launch-or-focus" "Kate" "uwsm" "app" "--"
            "${pkgs.kdePackages.kate}/bin/kate";
          "Mod+O".action = spawn "launch-or-focus" "Obsidian" "uwsm" "app" "--" "obsidian";
          "Mod+T".action = spawn "uwsm" "app" "--" "alacritty" "-e" "btop";
          "Mod+D".action = spawn "uwsm" "app" "--" "alacritty" "-e" "lazydocker";
          "Mod+G".action = spawn "launch-or-focus" "vesktop" "uwsm" "app" "--" "vesktop";
          # firefoxpwa shortcuts disabled
          # "Mod+Shift+G".action =
          #   spawn "launch-or-focus" "Grok" "uwsm" "app" "--" "firefoxpwa" "site" "launch"
          #   "grok";
          "Mod+A".action = spawn "launch-or-focus" "LM" "uwsm" "app" "--" "lm-studio";
          # "Mod+Shift+A".action =
          #   spawn "launch-or-focus" "ChatGPT" "uwsm" "app" "--" "firefoxpwa" "site" "launch"
          #   "chatgpt";
          "Mod+M".action =
            spawn "launch-or-focus" "Spotify" "uwsm" "app" "--" "flatpak" "run"
            "com.spotify.Client";
          "Mod+Shift+M".action = spawn "launch-or-focus" "Caprine" "uwsm" "app" "--" "caprine";
          "Mod+Slash".action =
            spawn "launch-or-focus" "Bitwarden" "uwsm" "app" "--" "flatpak" "run"
            "com.bitwarden.desktop";

           # Voice dictation - push-to-talk
           "Mod+Alt+V".action = spawn-sh "voxtype record toggle";
 
           # Remove redundant Mod+K (Mod+Alt+Space already opens settings)
           "Mod+Space".action = spawn "noctalia msg panel-toggle launcher";
           "Mod+Ctrl+E".action = spawn "noctalia msg panel-toggle launcher";
           "Mod+Ctrl+Slash".action = spawn "noctalia msg panel-toggle launcher";
           "Mod+Shift+Slash".action = spawn "noctalia msg window-switcher";
 
           "Mod+S".action = spawn "scratchpad-toggle";
           "Mod+Comma".action = spawn "noctalia msg notification-clear-active";
           "Mod+Alt+Space".action = spawn "noctalia msg settings-toggle";
           "Mod+Shift+Space".action = spawn "noctalia msg bar-toggle";
           "Mod+Ctrl+A".action = spawn "noctalia msg panel-toggle control-center audio";
           "Mod+Ctrl+W".action = spawn "noctalia msg panel-toggle control-center network";
           "Mod+Ctrl+B".action = spawn "noctalia msg panel-toggle control-center bluetooth";
           "Mod+Ctrl+I".action = spawn "noctalia msg caffeine-toggle";
           "Mod+Ctrl+N".action = spawn "noctalia msg nightlight-toggle";
           "Mod+Ctrl+D".action = spawn "noctalia msg theme-mode-toggle";
           "Mod+Ctrl+T".action = spawn "noctalia msg panel-toggle control-center system";
           "Mod+Ctrl+S".action = spawn "noctalia msg panel-toggle control-center share";
           "Mod+Ctrl+L".action = spawn "noctalia msg session lock";
           "Mod+Ctrl+O".action = spawn "noctalia msg panel-toggle control-center";
           "Mod+Ctrl+Shift+W".action = spawn "noctalia msg wallpaper-random";
           "Mod+Shift+Comma".action = spawn "noctalia msg notification-clear-active";
           "Mod+Ctrl+Comma".action = spawn "noctalia msg notification-dnd-toggle";
           "Mod+Alt+Comma".action = spawn "noctalia msg notification-dnd-status";
           "Mod+Alt+Shift+Comma".action = spawn "noctalia msg notification-invoke-latest";

          # Screenshots (smart region, window, fullscreen, color)
          "Print".action = spawn "noctalia" "msg" "screenshot-region";
          "Mod+Print" = {
            action.spawn = [
              "screenshot"
              "color"
            ];
          };
          "Mod+Ctrl+Print" = {
            action.spawn = ["ocr-extract"];
          };
          "Mod+Shift+Print".action = spawn "noctalia" "msg" "screenshot-fullscreen";
          "Mod+Alt+Print" = {
            action.spawn = [
              "screenshot"
              "window"
            ];
          };
          "Mod+Ctrl+Shift+Print".action = spawn "niri" "msg" "action" "screenshot-screen";

          # Screen recording (toggle: run to start, run again to stop)
          "Alt+Print" = {
            action.spawn = ["screenrecord"];
          };
          "Mod+Alt+Shift+Print" = {
            action.spawn = [
              "screenrecord"
              "desktop"
            ];
          };

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

          "Mod+F".action = fullscreen-window;
          "Mod+Shift+F".action = maximize-column;
          "Mod+V".action = spawn "uwsm" "app" "--" "copyq" "show";
          "Mod+Shift+V".action = switch-focus-between-floating-and-tiling;

          # Zowie (DP-5) - Main monitor - focus workspace 1-4
          "Mod+1".action = spawn-sh "niri msg action focus-monitor DP-5 && niri msg action focus-workspace 1";
          "Mod+2".action = spawn-sh "niri msg action focus-monitor DP-5 && niri msg action focus-workspace 2";
          "Mod+3".action = spawn-sh "niri msg action focus-monitor DP-5 && niri msg action focus-workspace 3";
          "Mod+4".action = spawn-sh "niri msg action focus-monitor DP-5 && niri msg action focus-workspace 4";
          # ASUS (DP-4) - Secondary - focus workspace 1-2
          "Mod+5".action = spawn-sh "niri msg action focus-monitor DP-4 && niri msg action focus-workspace 1";
          "Mod+6".action = spawn-sh "niri msg action focus-monitor DP-4 && niri msg action focus-workspace 2";
          # Acer (DP-6) - Tertiary - focus workspace 1-2
          "Mod+7".action = spawn-sh "niri msg action focus-monitor DP-6 && niri msg action focus-workspace 1";
          "Mod+8".action = spawn-sh "niri msg action focus-monitor DP-6 && niri msg action focus-workspace 2";
          # Samsung (HDMI-A-2) - TV - focus workspace 1-2
          "Mod+9".action =
            spawn-sh "niri msg action focus-monitor HDMI-A-2 && niri msg action focus-workspace 1";
          "Mod+0".action =
            spawn-sh "niri msg action focus-monitor HDMI-A-2 && niri msg action focus-workspace 2";

          # Move column to workspace N on a specific monitor (cross-monitor)
          "Mod+Shift+1".action = spawn-sh "niri-move-to-workspace.sh DP-5 1";
          "Mod+Shift+2".action = spawn-sh "niri-move-to-workspace.sh DP-5 2";
          "Mod+Shift+3".action = spawn-sh "niri-move-to-workspace.sh DP-5 3";
          "Mod+Shift+4".action = spawn-sh "niri-move-to-workspace.sh DP-5 4";
          "Mod+Shift+5".action = spawn-sh "niri-move-to-workspace.sh DP-4 1";
          "Mod+Shift+6".action = spawn-sh "niri-move-to-workspace.sh DP-4 2";
          "Mod+Shift+7".action = spawn-sh "niri-move-to-workspace.sh DP-6 1";
          "Mod+Shift+8".action = spawn-sh "niri-move-to-workspace.sh DP-6 2";
          "Mod+Shift+9".action = spawn-sh "niri-move-to-workspace.sh HDMI-A-2 1";
          "Mod+Shift+0".action = spawn-sh "niri-move-to-workspace.sh HDMI-A-2 2";
          "Mod+Page_Down".action = focus-workspace-down;
          "Mod+Page_Up".action = focus-workspace-up;
          "Mod+Shift+Page_Down".action = move-column-to-workspace-down;
          "Mod+Shift+Page_Up".action = move-column-to-workspace-up;

          "Mod+Tab".action = focus-workspace-down;
          "Mod+Shift+Tab".action = focus-workspace-up;
          "Mod+Ctrl+Tab".action = focus-workspace-previous;

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

          # ── Media keys ──────────────────────────────────────────────
          # 2026-07-07: reverted to spawn-sh per the original
          # commit 889f612f ("fix: change XF86 media key bindings from
          # spawn to spawn-sh"). spawn argv-tokenizes the string and
          # exec's the joined string as a single binary name — i.e. it
          # looks for an executable literally named
          # "noctalia msg volume-up", which fails. spawn-sh routes
          # through `sh -c` so the spaces split correctly. Same fix
          # shape as the prior commit; +XF86MonBrightnessUp/Down which
          # were never wired (the captured card has dedicated
          # brightness keys).
          "XF86AudioRaiseVolume".action = spawn-sh "noctalia msg volume-up";
          "XF86AudioLowerVolume".action = spawn-sh "noctalia msg volume-down";
          "XF86AudioMute".action = spawn-sh "noctalia msg volume-mute";
          "XF86AudioMicMute".action = spawn-sh "noctalia msg mic-mute";
          "XF86AudioPlay".action = spawn-sh "noctalia msg media toggle";
          "XF86AudioNext".action = spawn-sh "noctalia msg media next";
          "XF86AudioPrev".action = spawn-sh "noctalia msg media previous";
          "XF86AudioStop".action = spawn-sh "noctalia msg media stop";
          # Brightness media keys — routed through the noctalia wrapper.
          # The wrapper forwards global verbs (no target arg) to
          # brightness-router.sh so the patched niri output (locked-I2C
          # Samsung HDTV on HDMI-A-2) still gets sdr-brightness.
          "XF86MonBrightnessUp".action = spawn-sh "noctalia msg brightness-up";
          "XF86MonBrightnessDown".action = spawn-sh "noctalia msg brightness-down";

          "Mod+Escape".action = spawn "noctalia msg panel-toggle session";
          "Mod+Ctrl+Escape".action = spawn "systemctl" "suspend";
          "Mod+Shift+Escape".action = quit;
          "Mod+Shift+C".action = spawn "niri" "msg" "action" "load-config-file";
          "Ctrl+Alt+Delete".action =
            spawn-sh ''for wid in $(niri msg windows 2>/dev/null | grep -oP 'Window ID \\K[0-9]+'); do niri msg action close-window --id "$wid"; done'';
        };

        window-rules = [
          # ═══════════════════════════════════════════════════════════════
          # FLOATING — system dialogs, auth, file pickers, overlays
          # ═══════════════════════════════════════════════════════════════
          {
            matches = [
              {app-id = "pavucontrol";}
              {app-id = "nm-connection-editor";}
              {app-id = "blueman-manager";}
              {app-id = "gnome-calculator";}
              {app-id = "gnome-control-center";}
              {app-id = "org.kde.kinfocenter";}
              {app-id = "file-roller";}
              {app-id = "org.kde.ark";}
              {app-id = "pinentry-";}
              {title = "File Transfer*";}
              {title = "Authentication*";}
            ];
            open-floating = true;
          }
          # Polkit auth agent
          {
            matches = [
              {app-id = "org.kde.polkit-kde-authentication-agent-1";}
              {title = ".*Authentication Required.*";}
            ];
            open-floating = true;
          }
          # GTK/Qt file chooser dialogs from any app
          {
            matches = [
              {title = "Open (.*Files?|Folder).*";}
              {title = "Save (.*Files?|As).*";}
              {title = "Select.*";}
              {title = "Choose.*";}
              {title = "Rename.*";}
              {title = "Properties.*";}
              {
                app-id = "org.kde.dolphin";
                title = "Open.*";
              }
              {
                app-id = "org.kde.dolphin";
                title = "Save.*";
              }
              {
                app-id = "org.kde.dolphin";
                title = "Copy.*";
              }
              {
                app-id = "org.kde.dolphin";
                title = "Move.*";
              }
              {
                app-id = "org.kde.dolphin";
                title = "Delete.*";
              }
              {app-id = "org.gtk.FileChooserDialog";}
              {app-id = "xdg-desktop-portal-gtk";}
            ];
            open-floating = true;
            default-column-width = {
              fixed = 900;
            };
            default-window-height = {
              fixed = 600;
            };
          }
          # Screen share picker
          {
            matches = [{title = "Choose what to share";}];
            open-floating = true;
          }
          # Picture-in-Picture overlays — float, pin top-left
          {
            matches = [{title = "Picture-in-Picture";}];
            open-floating = true;
            default-floating-position = {
              x = 10;
              y = 10;
              relative-to = "top-left";
            };
            default-column-width = {
              fixed = 400;
            };
            default-window-height = {
              fixed = 225;
            };
          }
          # Steam notification toasts — position top-right
          {
            matches = [
              {
                app-id = "steam";
                title = "notificationtoasts_.*_desktop";
              }
            ];
            open-floating = true;
            default-floating-position = {
              x = 10;
              y = 10;
              relative-to = "top-right";
            };
          }

          # ═══════════════════════════════════════════════════════════════
          # TILING WIDTHS — per-app column proportions
          # ═══════════════════════════════════════════════════════════════
          # Browsers — full width
          {
            matches = [
              {app-id = "firefox";}
              {app-id = "zen-twilight";}
              {app-id = "librewolf";}
              {app-id = "chromium";}
              {app-id = "brave";}
            ];
            default-column-width = {
              proportion = 1.0;
            };
          }
          # Terminals — half width
          {
            matches = [
              {app-id = "Alacritty";}
              {app-id = "kitty";}
              {app-id = "foot";}
              {app-id = "gnome-terminal";}
            ];
            default-column-width = {
              proportion = 0.5;
            };
          }
          # IDEs and editors — 70%
          {
            matches = [
              {app-id = "code";}
              {app-id = "code-url-handler";}
              {app-id = "jetbrains-";}
              {app-id = "emacs";}
              {app-id = "obsidian";}
            ];
            default-column-width = {
              proportion = 0.7;
            };
          }
          # Chat/messaging — 50% (compact, chat doesn't need width)
          {
            matches = [
              {app-id = "vesktop";}
              {app-id = "caprine";}
              {app-id = "telegram.desktop";}
              {app-id = "org.telegram.desktop";}
              {app-id = "Signal";}
            ];
            default-column-width = {
              proportion = 0.5;
            };
          }
          # Media players — 65%
          {
            matches = [
              {app-id = "spotify";}
              {app-id = "mpv";}
              {app-id = "vlc";}
              {app-id = "org.kde.audiotube";}
            ];
            default-column-width = {
              proportion = 0.65;
            };
          }
          # System monitors — 40% (narrow, data-dense)
          {
            matches = [
              {app-id = "org.kde.systemmonitor";}
            ];
            default-column-width = {
              proportion = 0.4;
            };
          }

          # ═══════════════════════════════════════════════════════════════
          # PRIVACY — block screen capture for sensitive windows
          # ═══════════════════════════════════════════════════════════════
          {
            matches = [
              {app-id = "bitwarden";}
              {app-id = "Bitwarden";}
              {app-id = "keepassxc";}
              {app-id = "1password";}
              {title = ".*Password.*";}
              {title = ".*Secret.*";}
            ];
            block-out-from = "screen-capture";
          }

          # ═══════════════════════════════════════════════════════════════
          # GAMING — route to TV (HDMI-A-2), fullscreen
          # ═══════════════════════════════════════════════════════════════
          {
            matches = [{app-id = ".*GenshinImpact.*";}];
            open-on-output = "HDMI-A-2";
            open-fullscreen = true;
          }
          {
            matches = [
              {
                app-id = "steam";
                title = "Steam$";
              }
            ];
            open-on-output = "HDMI-A-2";
            open-fullscreen = true;
          }
          {
            matches = [
              {app-id = "moe.launcher.an-anime-game-launcher";}
              {app-id = "moe.launcher.the-honkers-railway-launcher";}
              {app-id = "lutris";}
              {app-id = "heroic";}
              {app-id = "minecraft";}
              {app-id = "prism-launcher";}
              {app-id = "com.libretro.RetroArch";}
              {app-id = "com.moonlight_stream.Moonlight";}
            ];
            open-on-output = "HDMI-A-2";
          }
          # Steam popup dialogs — tile normally on TV (settings, friends, etc.)
          {
            matches = [
              {
                app-id = "steam";
                title = "Settings";
              }
              {
                app-id = "steam";
                title = "Friends";
              }
              {
                app-id = "steam";
                title = "Chat";
              }
              {
                app-id = "steam";
                title = "Properties*";
              }
              {
                app-id = "steam";
                title = "Steam Guard*";
              }
              {
                app-id = "steam";
                title = "Screenshot*";
              }
              {
                app-id = "steam";
                title = "Add a Game*";
              }
              {
                app-id = "steam";
                title = "Install*";
              }
              {
                app-id = "steam";
                title = "Uninstall*";
              }
              {
                app-id = "steam";
                title = "Back Up*";
              }
              {
                app-id = "steam";
                title = "Create or select*";
              }
              {
                app-id = "steam";
                title = "Select*";
              }
            ];
            open-maximized = true;
          }
          # CopyQ - clipboard manager (floating)
          {
            matches = [{app-id = "copyq";}];
            open-floating = true;
          }
        ];

        layer-rules = [
          {
            matches = [{namespace = "noctalia.*";}];
            place-within-backdrop = false;
          }
          {
            matches = [{namespace = "quickshell.*";}];
            place-within-backdrop = false;
          }
          {
            matches = [{namespace = "gtk-layer-shell";}];
            place-within-backdrop = false;
          }
        ];
      }
    )
    (mkIf ((config.stylix.enable or false) && (config.lib.stylix ? colors)) {
      cursor = mkIf (config.stylix.cursor or null != null) {
        size = mkDefault config.stylix.cursor.size;
        theme = mkDefault config.stylix.cursor.name;
      };
      layout = with (config.lib.stylix.colors.withHashtag or {}); {
        focus-ring.enable = mkDefault false;
        border = {
          enable = mkDefault true;
          active = {color = mkDefault (if base0D != null then base0D else "#7aa2f7");};
          inactive = {color = mkDefault (if base03 != null then base03 else "#3b4261");};
        };
      };
    })
    (mkIf (hostName == "zephyr") {
      # Zephyr: 4 monitors (main + secondary + tertiary + TV)
      outputs = {
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
    })
    (mkIf (hostName == "sentry" || hostName == "forge") {
      # Sentry/Forge: single 900p monitor
      outputs = {
        "*" = {
          scale = 1.0;
        };
      };
    })
    (mkIf (hostName == "nexus") {
      # Nexus: single 4K monitor (3840x2160@60)
      outputs = {
        "HDMI-A-1" = {
          mode = {
            width = 3840;
            height = 2160;
            refresh = 60.0;
          };
          position = {
            x = 0;
            y = 0;
          };
          scale = 1.5;
        };
      };
    })
  ]);

  # Auto-reload noctalia systemd unit is registered upstream. The ExecStart
  # override (sources /etc/uwsm/env-niri + discovers NIRI_SOCKET) lives in
  # modules/desktop/wayland-compositor-common.nix so it applies to every
  # niri-enabled host, not just zephyr.

  # Auto-reload niri config when home-manager swaps ~/.config/niri/config.kdl
  # (the symlink target moves to a new /nix/store generation on every switch).
  # systemd path watches the PARENT DIRECTORY (not the symlink itself --
  # systemd resolves symlinks on PathChanged= and would pin the OLD store
  # path, never seeing the new generation).
  systemd.user.paths.niri-config-reload = mkIf niriHmAvailable {
    Unit.Description = "Watch ~/.config/niri/ for config.kdl generation swap";
    # Watching the parent dir fires whenever HM tmpfile-then-rename replaces
    # the config.kdl symlink. Atomic-ish (single PathChanged on rename).
    # `default.target` (not graphical-session.target) so the watch is
    # active from login onward. Path unit must be ready before any
    # potential HM swap during graphical-session startup.
    Install.WantedBy = [ "default.target" ];
    Path.PathChanged = "${config.home.homeDirectory}/.config/niri";
  };

  systemd.user.services.niri-config-reload = mkIf niriHmAvailable {
    Unit.Description = "Reload niri config after config.kdl generation swap";
    Service = {
      Type = "oneshot";
      # Guard: pgrep niri first so path-triggered reloads during early login
      # (before niri-session is up) or after a niri crash don't spam journal
      # with `niri msg` connection errors. Idempotent -- next path event
      # retries once niri is back.
      ExecStart = pkgs.writeShellScript "niri-reload-on-config-change" ''
        #!/bin/sh
        if ${pkgs.procps}/bin/pgrep -x niri >/dev/null 2>&1; then
          ${pkgs.niri}/bin/niri msg action load-config-file \
            || echo "niri-reload-on-config-change: reload failed" >&2
        fi
      '';
    };
  };

  # Declarative launch-or-focus script with orphan cleanup
  home.file.".local/bin/launch-or-focus" = {
    executable = true;
    text = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      if [ $# -lt 1 ]; then
        echo "Usage: launch-or-focus <window-pattern> [launch-command] [args...]" >&2
        exit 1
      fi

      PATTERN="$1"
      shift || true
      LAUNCH_CMD="''${@:-$PATTERN}"

      # Kill orphan processes that match the pattern but have no Niri window.
      # Prevents stale processes from a previous session blocking new launches.
      for pid in $(pgrep -f "$PATTERN" 2>/dev/null || true); do
        if [ "$pid" != "$$" ] && ! ${pkgs.niri}/bin/niri msg windows 2>/dev/null | grep -q "PID: $pid"; then
          kill "$pid" 2>/dev/null || true
        fi
      done

      find_window_id() {
        local pat_lower=$(echo "$PATTERN" | tr '[:upper:]' '[:lower:]')
        ${pkgs.niri}/bin/niri msg windows 2>/dev/null | awk -v pat="$pat_lower" '
          /^Window ID/ { current_id = $3; gsub(/:/, "", current_id); title=""; appid="" }
          /^  Title:/ {
            val = $0; sub(/^  Title: "/, "", val); sub(/"$/, "", val); title = val
          }
          /^  App ID:/ {
            val = $0; sub(/^  App ID: "/, "", val); sub(/"$/, "", val); appid = val
            if (tolower(title) ~ pat || tolower(appid) ~ pat) {
              print current_id; exit
            }
          }
        '
      }

      WINDOW_ID=$(find_window_id) || true
      if [ -n "$WINDOW_ID" ]; then
        ${pkgs.niri}/bin/niri msg action focus-window --id "$WINDOW_ID" 2>/dev/null || true
      else
        exec $LAUNCH_CMD
      fi
    '';
  };
}
