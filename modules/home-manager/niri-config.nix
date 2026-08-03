# Niri compositor configuration — core settings (cursor, layout, input,
# window-rules, layer-rules, stylix integration, config-reload service,
# launch-or-focus + alacritty-oom-safe helper scripts).
#
# Extracted sub-modules (audit F-22, 2026-07-29):
#   ./niri-spawn.nix       — spawn-at-startup apps (polkit, noctalia, ckb-next)
#   ./niri-outputs.nix     — per-host multi-monitor output config
#   ./niri-keybinds.nix    — all keyboard shortcuts (~200 lines)
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}: let
  inherit (lib) mkDefault mkIf;
  # NOTE: `inputs.niri.homeModules.config` is unconditionally imported for
  # niri hosts (zephyr/sentry) in modules/system/home-manager.nix, so the
  # `programs.niri.settings` option and `config.lib.niri` are ALWAYS present
  # here. The old `config.lib ? niri` guard evaluated false during early HM
  # evaluation and silently dropped the ENTIRE settings block -- leaving a
  # 23-byte config.kdl (`include "noctalia.kdl"`) with no keyboard-repeat,
  # input, layout, or window-rules. Removing the guard so settings always apply.
in {
  imports = [
    ./niri-spawn.nix
    ./niri-outputs.nix
    ./niri-keybinds.nix
  ];

  programs.niri.settings = lib.mkMerge [
    {
      cursor = {
        # theme/size are owned by Stylix (see stylix block below) so the
        # cursor follows the active scheme instead of a hardcoded name.
        hide-on-key-press = true;
        hide-after-inactive-ms = 3000;
      };

      hotkey-overlay = {
        skip-at-startup = false;
        hide-not-bound = true;
      };

      prefer-no-csd = true;

      layout = {
        # focus-ring/border colors are owned by Stylix (see stylix block
        # below) so the window accent follows the active scheme.
        default-column-width = {
          proportion = 0.5;
        };
        center-focused-column = "never";
        gaps = 8;
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
    (mkIf ((config.stylix.enable or false) && (config.lib.stylix ? colors)) {
      cursor = mkIf (config.stylix.cursor or null != null) {
        size = mkDefault config.stylix.cursor.size;
        theme = mkDefault config.stylix.cursor.name;
      };
      layout = with (config.lib.stylix.colors.withHashtag or {}); {
        # Stylix drives the focus-ring colors; preserve the user's preferred
        # look (focus-ring on, border off) while making the hue follow the
        # active base16 scheme instead of a hardcoded Tokyo Night palette.
        focus-ring = {
          enable = mkDefault true;
          width = mkDefault 2;
          active = {
            color = mkDefault (
              if base0D != null
              then base0D
              else "#7aa2f7"
            );
          };
          inactive = {
            color = mkDefault (
              if base03 != null
              then base03
              else "#3b4261"
            );
          };
        };
        border = {
          enable = mkDefault false;
        };
      };
    })
  ];

  # Auto-reload noctalia systemd unit is registered upstream. The ExecStart
  # override (sources /etc/uwsm/env-niri + discovers NIRI_SOCKET) lives in
  # modules/desktop/wayland-compositor-common.nix so it applies to every
  # niri-enabled host, not just zephyr.

  # Auto-reload niri config when home-manager swaps ~/.config/niri/config.kdl
  # (the symlink target moves to a new /nix/store generation on every switch).
  # systemd path watches the PARENT DIRECTORY (not the symlink itself --
  # systemd resolves symlinks on PathChanged= and would pin the OLD store
  # path, never seeing the new generation).
  systemd.user.paths.niri-config-reload = {
    Unit.Description = "Watch ~/.config/niri/ for config.kdl generation swap";
    # Watching the parent dir fires whenever HM tmpfile-then-rename replaces
    # the config.kdl symlink. Atomic-ish (single PathChanged on rename).
    # `default.target` (not graphical-session.target) so the watch is
    # active from login onward. Path unit must be ready before any
    # potential HM swap during graphical-session startup.
    Install.WantedBy = ["default.target"];
    Path.PathChanged = "${config.home.homeDirectory}/.config/niri";
  };

  systemd.user.services.niri-config-reload = {
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

  # Declarative launch-or-focus script with orphan cleanup.
  #
  # Installed as a home.packages derivation (NOT home.file under ~/.local/bin)
  # so it lands in /etc/profiles/per-user/<user>/bin — which IS present in the
  # PATH that niri passes to spawned children. A bare `home.file` under
  # ~/.local/bin is NOT on that PATH, so niri-spawned binds calling
  # `launch-or-focus` by bare name silently fail to find the script.
  #
  # writeShellScriptBin (not writeShellApplication) is used deliberately: it
  # produces <name>/bin/<name> without running shellcheck, so the inline
  # `local x=$(...)` form builds cleanly on this Nixpkgs version.
  home.packages = [
    # 2026-07-27 OOM emergency: on zephyr (31 GB RAM, persistent pressure
    # from control-plane + gaming + AI + mining), systemd-oomd marked the
    # uwsm-spawned alacritty scope as a victim at 90% mem+swap threshold.
    # Wrap alacritty in a NEW --user scope under systemd-run so it's a
    # clearly-bounded leaf cgroup with its own caps and OOM-score. The
    # uwsm outer scope may still die, but alacritty's branch terminates
    # cleanly rather than dragging niri or noctalia with it.
    # Mirrors the systemd-run ownership pattern in
    # modules/gaming/gaming.nix (launch-game wrapper, line ~425).
    (pkgs.writeShellScriptBin "alacritty-oom-safe" ''
      #!/bin/sh
      set -euo pipefail
      if [ "$#" -eq 0 ]; then
        set -- alacritty
      fi
      exec ${pkgs.systemd}/bin/systemd-run --user --scope --collect \
        --property=MemoryHigh=2G \
        --property=MemoryMax=4G \
        --property=OOMPolicy=continue \
        --property=OOMScoreAdjust=-800 \
        -- alacritty "$@"
    '')
    (pkgs.writeShellScriptBin "launch-or-focus" ''
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
        if [ "$pid" != "$$" ] && ! niri msg windows 2>/dev/null | grep -q "PID: $pid"; then
          kill "$pid" 2>/dev/null || true
        fi
      done

      find_window_id() {
        local pat_lower
        pat_lower=$(echo "$PATTERN" | tr '[:upper:]' '[:lower:]')
        niri msg windows 2>/dev/null | awk -v pat="$pat_lower" '
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
        niri msg action focus-window --id "$WINDOW_ID" 2>/dev/null || true
      else
        exec $LAUNCH_CMD
      fi
    '')
  ];
}
