# Hyprland Keybindings - Omarchy-inspired patterns
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
      "$mainMod, Return, exec, ${pkgs.kitty}/bin/kitty"
      "$mainMod SHIFT, Return, exec, ${pkgs.kitty}/bin/kitty"
      "$mainMod, W, killactive"
      "$mainMod SHIFT, W, exec, pkill -9 kitty"
      "$mainMod, Escape, exec, ${pkgs.wlogout}/bin/wlogout"
      "$mainMod SHIFT, Escape, exec, ${pkgs.swaylock-effects}/bin/swaylock -f -c $base00"
      "$mainMod, L, exec, ${pkgs.swaylock-effects}/bin/swaylock-effects"
      "$mainMod SHIFT, R, exec, pkill hyprland && dispatch exit"

      # ============================================================
      # APPLICATION LAUNCHERS
      # ============================================================
      "$mainMod, D, exec, ${pkgs.rofi}/bin/rofi -show drun"
      "$mainMod SHIFT, D, exec, ${pkgs.rofi}/bin/rofi -show window"
      "$mainMod, A, exec, ${pkgs.rofi}/bin/rofi -show apps"
      "$mainMod, K, exec, ${pkgs.rofi}/bin/rofi -show file"
      "$mainMod, E, exec, ${pkgs.thunar}/bin/thunar"
      "$mainMod, F, exec, zen"
      "$mainMod, C, exec, ${pkgs.vscodium}/bin/codium"
      "$mainMod, N, exec, vesktop"

      # ============================================================
      # WINDOW MANAGEMENT (Omarchy patterns)
      # ============================================================
      "$mainMod, T, togglefloating"
      "$mainMod, P, pseudo"
      "$mainMod, X, togglesplit"
      "$mainMod, F, fullscreen, 0"
      "$mainMod SHIFT, F, fullscreen, 1"
      "$mainMod, Space, togglefloating"

      # Omarchy: Window grouping
      "$mainMod, G, togglegroup"
      "$mainMod SHIFT, G, moveintogroup"
      "$mainMod ALT, left, changegroupactive, b"
      "$mainMod ALT, right, changegroupactive, f"
      "$mainMod ALT, up, changegroupactive, u"
      "$mainMod ALT, down, changegroupactive, d"

      # Omarchy: Scratchpad workspace
      "$mainMod, S, togglespecialworkspace, scratchpad"
      "$mainMod SHIFT, S, movetoworkspacesilent, special"

      # Focus movement (Vim-style)
      "$mainMod, h, movefocus, l"
      "$mainMod, j, movefocus, d"
      "$mainMod, k, movefocus, u"
      "$mainMod, l, movefocus, r"
      "$mainMod, left, movefocus, l"
      "$mainMod, down, movefocus, d"
      "$mainMod, up, movefocus, u"
      "$mainMod, right, movefocus, r"

      # Move windows
      "$mainMod SHIFT, h, movewindow, l"
      "$mainMod SHIFT, j, movewindow, d"
      "$mainMod SHIFT, k, movewindow, u"
      "$mainMod SHIFT, l, movewindow, r"
      "$mainMod SHIFT, left, movewindow, l"
      "$mainMod SHIFT, down, movewindow, d"
      "$mainMod SHIFT, up, movewindow, u"
      "$mainMod SHIFT, right, movewindow, r"

      # Resize windows (Omarchy: uses = and - keys)
      "$mainMod, equal, resizeactive, 80 0"
      "$mainMod, minus, resizeactive, -80 0"
      "$mainMod SHIFT, equal, resizeactive, 0 80"
      "$mainMod SHIFT, minus, resizeactive, 0 -80"

      # Move windows
      "$mainMod ALT, h, moveactive, -80 0"
      "$mainMod ALT, j, moveactive, 0 80"
      "$mainMod ALT, k, moveactive, 0 -80"
      "$mainMod ALT, l, moveactive, 80 0"

      # ============================================================
      # WORKSPACES (Omarchy: uses code:10-19 for numbers 1-9 and 0)
      # ============================================================
      "$mainMod, code:10, workspace, 1"
      "$mainMod, code:11, workspace, 2"
      "$mainMod, code:12, workspace, 3"
      "$mainMod, code:13, workspace, 4"
      "$mainMod, code:14, workspace, 5"
      "$mainMod, code:15, workspace, 6"
      "$mainMod, code:16, workspace, 7"
      "$mainMod, code:17, workspace, 8"
      "$mainMod, code:18, workspace, 9"
      "$mainMod, code:19, workspace, 10"

      # Move to workspace
      "$mainMod SHIFT, code:10, movetoworkspace, 1"
      "$mainMod SHIFT, code:11, movetoworkspace, 2"
      "$mainMod SHIFT, code:12, movetoworkspace, 3"
      "$mainMod SHIFT, code:13, movetoworkspace, 4"
      "$mainMod SHIFT, code:14, movetoworkspace, 5"
      "$mainMod SHIFT, code:15, movetoworkspace, 6"
      "$mainMod SHIFT, code:16, movetoworkspace, 7"
      "$mainMod SHIFT, code:17, movetoworkspace, 8"
      "$mainMod SHIFT, code:18, movetoworkspace, 9"
      "$mainMod SHIFT, code:19, movetoworkspace, 10"

      # Workspace navigation
      "$mainMod, bracketleft, workspace, -1"
      "$mainMod, bracketright, workspace, +1"
      "$mainMod SHIFT, bracketleft, movetoworkspace, -1"
      "$mainMod SHIFT, bracketright, movetoworkspace, +1"

      # ============================================================
      # SCREENSHOTS & RECORDING
      # ============================================================
      ", Print, exec, ${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy"
      "$mainMod, Print, exec, ${pkgs.grim}/bin/grim -g \"\$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy"
      "$mainMod SHIFT, Print, exec, ${pkgs.grim}/bin/grim -g \"\$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png"
      "$mainMod CTRL, Print, exec, ${pkgs.wf-recorder}/bin/wf-recorder -f ~/Video/screenrecord-$(date +%Y%m%d_%H%M%S).mp4"
      "$mainMod SHIFT, CTRL, R, exec, pkill -SIGINT wf-recorder"

      # ============================================================
      # WALLPAPER & APPEARANCE (Omarchy: uses B for background)
      # ============================================================
      "$mainMod, B, exec, ${pkgs.waypaper}/bin/waypaper"
      "$mainMod SHIFT, B, exec, ${pkgs.swww}/bin/swww img \$(${pkgs.rofi}/bin/rofi -show file)"
      "$mainMod CTRL, B, exec, ${pkgs.hyprpicker}/bin/hyprpicker -a"

      # ============================================================
      # MEDIA & VOLUME
      # ============================================================
      ", XF86AudioRaiseVolume, exec, ${pkgs.pamixer}/bin/pamixer -i 5"
      ", XF86AudioLowerVolume, exec, ${pkgs.pamixer}/bin/pamixer -d 5"
      ", XF86AudioMute, exec, ${pkgs.pamixer}/bin/pamixer -t"
      ", XF86AudioMicMute, exec, ${pkgs.pamixer}/bin/pamixer --default-source -m"
      ", XF86MonBrightnessUp, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%+"
      ", XF86MonBrightnessDown, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%-"
      ", XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
      ", XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next"
      ", XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous"

      # ============================================================
      # UTILITIES
      # ============================================================
      "$mainMod, V, exec, ${pkgs.rofi}/bin/rofi -show emoji"
      "$mainMod, comma, exec, ${pkgs.mako}/bin/makoctl dismiss"
      "$mainMod SHIFT, comma, exec, ${pkgs.mako}/bin/makoctl dismiss -a"
      "$mainMod, period, exec, ${pkgs.mako}/bin/makoctl restore"
      "$mainMod, Tab, exec, ${pkgs.rofi}/bin/rofi -show window"
      "$mainMod SHIFT, Tab, exec, ${pkgs.rofi}/bin/rofi -show windowcd"

      # Scroll through workspaces with mouse
      "$mainMod, mouse_down, workspace, e+1"
      "$mainMod, mouse_up, workspace, e-1"
    ];

    bindl = [
      # Lock when laptop closes
      ", switch:Lid Switch, exec, ${pkgs.swaylock-effects}/bin/swaylock -f -c $base00"
    ];

    binde = [
      # Volume keys with repeat
      ", XF86AudioRaiseVolume, exec, ${pkgs.pamixer}/bin/pamixer -i 5"
      ", XF86AudioLowerVolume, exec, ${pkgs.pamixer}/bin/pamixer -d 5"
    ];
  };
}
