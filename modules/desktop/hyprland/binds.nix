# Hyprland Keybindings - Omarchy-inspired patterns
# Uses bindd syntax for human-readable descriptions
{ pkgs, ... }:
{
  wayland.windowManager.hyprland.settings = {
    bindm = [
      "$mainMod, mouse:272, movewindow"
      "$mainMod, mouse:273, resizewindow"
    ];

    bind = [
      # ============================================================
      # SYSTEM & UTILITIES (Omarchy patterns)
      # ============================================================
      "$mainMod, Return, Open terminal, exec, ${pkgs.kitty}/bin/kitty"
      "$mainMod SHIFT, Return, Open terminal (new), exec, ${pkgs.kitty}/bin/kitty"
      "$mainMod, W, Close window, killactive"
      "$mainMod SHIFT, W, Close terminal, exec, pkill -9 kitty"
      "$mainMod, Escape, System menu, exec, ${pkgs.wlogout}/bin/wlogout"
      "$mainMod SHIFT, Escape, Lock screen, exec, ${pkgs.swaylock}/bin/swaylock -f -c $base00"
      "$mainMod, L, Lock screen (effects), exec, ${pkgs.swaylock-effects}/bin/swaylock-effects"
      "$mainMod SHIFT, R, Exit Hyprland, exec, pkill hyprland && dispatch exit"

      # ============================================================
      # APPLICATION LAUNCHERS
      # ============================================================
      "$mainMod, D, Launch application, exec, ${pkgs.rofi}/bin/rofi -show drun"
      "$mainMod SHIFT, D, Show windows, exec, ${pkgs.rofi}/bin/rofi -show window"
      "$mainMod, A, Show apps, exec, ${pkgs.rofi}/bin/rofi -show apps"
      "$mainMod, K, Show keybindings, exec, ${pkgs.rofi}/bin/rofi -show file"
      "$mainMod, E, File manager, exec, ${pkgs.thunar}/bin/thunar"
      "$mainMod, F, Firefox, exec, ${pkgs.firefox}/bin/firefox"
      "$mainMod, C, VSCodium, exec, ${pkgs.vscodium}/bin/codium"
      "$mainMod, N, Discord, exec, ${pkgs.discord}/bin/discord"

      # ============================================================
      # WINDOW MANAGEMENT (Omarchy patterns)
      # ============================================================
      "$mainMod, T, Toggle floating/tiling, togglefloating"
      "$mainMod, P, Pseudo tile, pseudo"
      "$mainMod, X, Toggle split direction, togglesplit"
      "$mainMod, F, Toggle fullscreen, fullscreen, 0"
      "$mainMod SHIFT, F, Toggle fullscreen (no decorations), fullscreen, 1"
      "$mainMod, Space, Toggle floating, togglefloating"

      # Omarchy: Window grouping
      "$mainMod, G, Toggle window grouping, togglegroup"
      "$mainMod SHIFT, G, Move to group, moveintogroup"
      "$mainMod ALT, left, Activate group left, changegroupactive, b"
      "$mainMod ALT, right, Activate group right, changegroupactive, f"
      "$mainMod ALT, up, Activate group up, changegroupactive, u"
      "$mainMod ALT, down, Activate group down, changegroupactive, d"

      # Omarchy: Scratchpad workspace
      "$mainMod, S, Toggle scratchpad, togglespecialworkspace, scratchpad"
      "$mainMod SHIFT, S, Move to scratchpad, movetoworkspacesilent, special"

      # Focus movement (Vim-style)
      "$mainMod, h, Focus left, movefocus, l"
      "$mainMod, j, Focus down, movefocus, d"
      "$mainMod, k, Focus up, movefocus, u"
      "$mainMod, l, Focus right, movefocus, r"
      "$mainMod, left, Focus left, movefocus, l"
      "$mainMod, down, Focus down, movefocus, d"
      "$mainMod, up, Focus up, movefocus, u"
      "$mainMod, right, Focus right, movefocus, r"

      # Move windows
      "$mainMod SHIFT, h, Move left, movewindow, l"
      "$mainMod SHIFT, j, Move down, movewindow, d"
      "$mainMod SHIFT, k, Move up, movewindow, u"
      "$mainMod SHIFT, l, Move right, movewindow, r"
      "$mainMod SHIFT, left, Move left, movewindow, l"
      "$mainMod SHIFT, down, Move down, movewindow, d"
      "$mainMod SHIFT, up, Move up, movewindow, u"
      "$mainMod SHIFT, right, Move right, movewindow, r"

      # Resize windows (Omarchy: uses = and - keys)
      "$mainMod, equal, Resize wider, resizeactive, 80 0"
      "$mainMod, minus, Resize narrower, resizeactive, -80 0"
      "$mainMod SHIFT, equal, Resize taller, resizeactive, 0 80"
      "$mainMod SHIFT, minus, Resize shorter, resizeactive, 0 -80"

      # Move windows
      "$mainMod ALT, h, Move left, moveactive, -80 0"
      "$mainMod ALT, j, Move down, moveactive, 0 80"
      "$mainMod ALT, k, Move up, moveactive, 0 -80"
      "$mainMod ALT, l, Move right, moveactive, 80 0"

      # ============================================================
      # WORKSPACES (Omarchy: uses code:10-19 for numbers 1-9 and 0)
      # ============================================================
      "$mainMod, code:10, Workspace 1, workspace, 1"
      "$mainMod, code:11, Workspace 2, workspace, 2"
      "$mainMod, code:12, Workspace 3, workspace, 3"
      "$mainMod, code:13, Workspace 4, workspace, 4"
      "$mainMod, code:14, Workspace 5, workspace, 5"
      "$mainMod, code:15, Workspace 6, workspace, 6"
      "$mainMod, code:16, Workspace 7, workspace, 7"
      "$mainMod, code:17, Workspace 8, workspace, 8"
      "$mainMod, code:18, Workspace 9, workspace, 9"
      "$mainMod, code:19, Workspace 10, workspace, 10"

      # Move to workspace
      "$mainMod SHIFT, code:10, Move to workspace 1, movetoworkspace, 1"
      "$mainMod SHIFT, code:11, Move to workspace 2, movetoworkspace, 2"
      "$mainMod SHIFT, code:12, Move to workspace 3, movetoworkspace, 3"
      "$mainMod SHIFT, code:13, Move to workspace 4, movetoworkspace, 4"
      "$mainMod SHIFT, code:14, Move to workspace 5, movetoworkspace, 5"
      "$mainMod SHIFT, code:15, Move to workspace 6, movetoworkspace, 6"
      "$mainMod SHIFT, code:16, Move to workspace 7, movetoworkspace, 7"
      "$mainMod SHIFT, code:17, Move to workspace 8, movetoworkspace, 8"
      "$mainMod SHIFT, code:18, Move to workspace 9, movetoworkspace, 9"
      "$mainMod SHIFT, code:19, Move to workspace 10, movetoworkspace, 10"

      # Workspace navigation
      "$mainMod, bracketleft, Previous workspace, workspace, -1"
      "$mainMod, bracketright, Next workspace, workspace, +1"
      "$mainMod SHIFT, bracketleft, Move to previous, movetoworkspace, -1"
      "$mainMod SHIFT, bracketright, Move to next, movetoworkspace, +1"

      # ============================================================
      # SCREENSHOTS & RECORDING
      # ============================================================
      ", Print, Screenshot screen, exec, ${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy"
      "$mainMod, Print, Screenshot region, exec, ${pkgs.grim}/bin/grim -g \"\$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy"
      "$mainMod SHIFT, Print, Screenshot region (swappy), exec, ${pkgs.grim}/bin/grim -g \"\$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png"
      "$mainMod CTRL, Print, Record screen, exec, ${pkgs.wf-recorder}/bin/wf-recorder -f ~/Video/screenrecord-$(date +%Y%m%d_%H%M%S).mp4"
      "$mainMod SHIFT, CTRL, R, Stop recording, exec, pkill -SIGINT wf-recorder"

      # ============================================================
      # WALLPAPER & APPEARANCE (Omarchy: uses B for background)
      # ============================================================
      "$mainMod, B, Wallpaper picker, exec, ${pkgs.waypaper}/bin/waypaper"
      "$mainMod SHIFT, B, Next wallpaper, exec, ${pkgs.swww}/bin/swww img \$(${pkgs.rofi}/bin/rofi -show file)"
      "$mainMod CTRL, B, Color picker, exec, ${pkgs.hyprpicker}/bin/hyprpicker -a"

      # ============================================================
      # MEDIA & VOLUME
      # ============================================================
      ", XF86AudioRaiseVolume, Volume up, exec, ${pkgs.pamixer}/bin/pamixer -i 5"
      ", XF86AudioLowerVolume, Volume down, exec, ${pkgs.pamixer}/bin/pamixer -d 5"
      ", XF86AudioMute, Toggle mute, exec, ${pkgs.pamixer}/bin/pamixer -t"
      ", XF86AudioMicMute, Toggle mic mute, exec, ${pkgs.pamixer}/bin/pamixer --default-source -m"
      ", XF86MonBrightnessUp, Brightness up, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%+"
      ", XF86MonBrightnessDown, Brightness down, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%-"
      ", XF86AudioPlay, Play/pause, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
      ", XF86AudioNext, Next track, exec, ${pkgs.playerctl}/bin/playerctl next"
      ", XF86AudioPrev, Previous track, exec, ${pkgs.playerctl}/bin/playerctl previous"

      # ============================================================
      # UTILITIES
      # ============================================================
      "$mainMod, V, Emoji picker, exec, ${pkgs.rofi}/bin/rofi -show emoji"
      "$mainMod, comma, Dismiss notification, exec, ${pkgs.mako}/bin/makoctl dismiss"
      "$mainMod SHIFT, comma, Dismiss all notifications, exec, ${pkgs.mako}/bin/makoctl dismiss -a"
      "$mainMod, period, Restore notification, exec, ${pkgs.mako}/bin/makoctl restore"
      "$mainMod, Tab, Show windows, exec, ${pkgs.rofi}/bin/rofi -show window"
      "$mainMod SHIFT, Tab, Show windows (cd), exec, ${pkgs.rofi}/bin/rofi -show windowcd"

      # Scroll through workspaces with mouse
      "$mainMod, mouse_down, Scroll workspace down, workspace, e+1"
      "$mainMod, mouse_up, Scroll workspace up, workspace, e-1"
    ];

    bindl = [
      # Lock when laptop closes
      ", switch:Lid Switch, Lock screen, exec, ${pkgs.swaylock}/bin/swaylock -f -c $base00"
    ];

    binde = [
      # Volume keys with repeat
      ", XF86AudioRaiseVolume, Volume up (repeat), exec, ${pkgs.pamixer}/bin/pamixer -i 5"
      ", XF86AudioLowerVolume, Volume down (repeat), exec, ${pkgs.pamixer}/bin/pamixer -d 5"
    ];
  };
}
