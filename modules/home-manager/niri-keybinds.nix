# Niri keybinds — all keyboard shortcuts extracted from
# modules/home-manager/niri-config.nix on 2026-07-29 per audit F-22
# (de-monolith niri-config.nix mega-module).
#
# All binds use `config.lib.niri.actions` (aliased as `acts`) so the
# action names are validated at eval time. The keybind shapes are:
#   - Application launchers (Mod+Return, Mod+B, Mod+E, Mod+G, ...)
#   - Workspace / monitor movement (Mod+1-9, Mod+Shift+1-9, ...)
#   - Window management (Mod+Q, Mod+Left/Right/Up/Down, ...)
#   - Media keys (XF86AudioRaiseVolume, ...)
#   - System / session (Mod+Escape, Mod+Ctrl+Escape, Mod+Shift+Escape)
#   - Screenshots (Print, Mod+Print, ...)
#   - Screen recording (Alt+Print, Mod+Alt+Shift+Print)
{ config, lib, pkgs, ... }:
# NOTE: Only imported on niri hosts; `programs.niri.settings` + `config.lib.niri.actions`
# always valid. Removed the `config.programs.niri.enable` guard that evaluated false
# and dropped ALL keybinds.
let
  acts = config.lib.niri.actions;
in {
  programs.niri.settings = {
    binds = with acts; {
      # 2026-07-27 OOM emergency: alacritty-oom-safe wrapper caps per-instance
      # memory + lowers oomd scoring (see home.packages entry in parent).
      "Mod+Return".action = spawn "uwsm" "app" "--" "alacritty-oom-safe";
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
      "Mod+T".action = spawn "uwsm" "app" "--" "alacritty-oom-safe" "-e" "btop";
      "Mod+D".action = spawn "uwsm" "app" "--" "alacritty-oom-safe" "-e" "lazydocker";
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
      "Mod+Space".action = spawn "noctalia" "msg" "panel-toggle" "launcher";
      "Mod+Ctrl+E".action = spawn "noctalia" "msg" "panel-toggle" "launcher";
      "Mod+Ctrl+Slash".action = spawn "noctalia" "msg" "panel-toggle" "launcher";
      "Mod+Shift+Slash".action = spawn "noctalia" "msg" "window-switcher";

      "Mod+S".action = spawn "scratchpad-toggle";
      "Mod+Comma".action = spawn "noctalia" "msg" "notification-clear-active";
      "Mod+Alt+Space".action = spawn "noctalia" "msg" "settings-toggle";
      "Mod+Shift+Space".action = spawn "noctalia" "msg" "bar-toggle";
      "Mod+Ctrl+A".action = spawn "noctalia" "msg" "panel-toggle" "control-center" "audio";
      "Mod+Ctrl+W".action = spawn "noctalia" "msg" "panel-toggle" "control-center" "network";
      "Mod+Ctrl+B".action = spawn "noctalia" "msg" "panel-toggle" "control-center" "bluetooth";
      "Mod+Ctrl+I".action = spawn "noctalia" "msg" "caffeine-toggle";
      "Mod+Ctrl+N".action = spawn "noctalia" "msg" "nightlight-toggle";
      "Mod+Ctrl+D".action = spawn "noctalia" "msg" "theme-mode-toggle";
      "Mod+Ctrl+T".action = spawn "noctalia" "msg" "panel-toggle" "control-center" "system";
      "Mod+Ctrl+S".action = spawn "noctalia" "msg" "panel-toggle" "control-center" "share";
      "Mod+Ctrl+L".action = spawn "noctalia" "msg" "session" "lock";
      "Mod+Ctrl+O".action = spawn "noctalia" "msg" "panel-toggle" "control-center";
      "Mod+Ctrl+Shift+W".action = spawn "noctalia" "msg" "wallpaper-random";
      "Mod+Shift+Comma".action = spawn "noctalia" "msg" "notification-clear-active";
      "Mod+Ctrl+Comma".action = spawn "noctalia" "msg" "notification-dnd-toggle";
      "Mod+Alt+Comma".action = spawn "noctalia" "msg" "notification-dnd-status";
      "Mod+Alt+Shift+Comma".action = spawn "noctalia" "msg" "notification-invoke-latest";

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
      # "Alt+Tab".action = focus-window-previous; # TODO: focus-window-previous is not available in current niri

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

      "Mod+Escape".action = spawn "noctalia" "msg" "panel-toggle" "session";
      "Mod+Ctrl+Escape".action = spawn "systemctl" "suspend";
      "Mod+Shift+Escape".action = quit;
      "Mod+Shift+C".action = spawn "niri" "msg" "action" "load-config-file";
      "Ctrl+Alt+Delete".action =
        spawn-sh ''for wid in $(niri msg windows 2>/dev/null | grep -oP 'Window ID \\K[0-9]+'); do niri msg action close-window --id "$wid"; done'';
    };
  };
}
