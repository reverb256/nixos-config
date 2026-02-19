# Hyprland Keybindings
{ pkgs, ... }:
{
  wayland.windowManager.hyprland.settings = {
    bindm = [
      "$mainMod, mouse:272, movewindow"
      "$mainMod, mouse:273, resizewindow"
    ];

    bind = [
      # ============================================================
      # SYSTEM & UTILITIES
      # ============================================================
      "$mainMod, Return, exec, ${pkgs.kitty}/bin/kitty"
      "$mainMod SHIFT, Return, exec, ${pkgs.kitty}/bin/kitty"
      "$mainMod, Q, killactive"
      "$mainMod SHIFT, Q, exec, pkill -9 kitty"
      "$mainMod, Escape, exec, ${pkgs.swaylock}/bin/swaylock -f -c $base00"
      "$mainMod SHIFT, Escape, exec, ${pkgs.wlogout}/bin/wlogout"
      "$mainMod, L, exec, ${pkgs.swaylock-effects}/bin/swaylock-effects"
      "$mainMod SHIFT, R, exec, pkill hyprland && dispatch exit"

      # ============================================================
      # APPLICATION LAUNCHERS
      # ============================================================
      "$mainMod, D, exec, ${pkgs.rofi-wayland}/bin/rofi -show drun"
      "$mainMod SHIFT, D, exec, ${pkgs.rofi-wayland}/bin/rofi -show window"
      "$mainMod, A, exec, ${pkgs.rofi-wayland}/bin/rofi -show apps"
      "$mainMod, E, exec, ${pkgs.thunar}/bin/thunar"
      "$mainMod, F, exec, ${pkgs.firefox}/bin/firefox"
      "$mainMod, C, exec, ${pkgs.vscodium}/bin/codium"
      "$mainMod, N, exec, ${pkgs.discord}/bin/discord"
      "$mainMod, S, exec, ${pkgs.spotify}/bin/spotify"

      # ============================================================
      # WINDOW MANAGEMENT
      # ============================================================
      "$mainMod, T, togglefloating"
      "$mainMod, P, pseudo"
      "$mainMod, X, togglesplit"
      "$mainMod, F, fullscreen, 0"
      "$mainMod SHIFT, F, fullscreen, 1"
      "$mainMod, Space, exec, hyprctl dispatch togglefloating"

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

      # Resize windows
      "$mainMod CTRL, h, resizeactive, -80 0"
      "$mainMod CTRL, j, resizeactive, 0 80"
      "$mainMod CTRL, k, resizeactive, 0 -80"
      "$mainMod CTRL, l, resizeactive, 80 0"
      "$mainMod ALT, h, moveactive, -80 0"
      "$mainMod ALT, j, moveactive, 0 80"
      "$mainMod ALT, k, moveactive, 0 -80"
      "$mainMod ALT, l, moveactive, 80 0"

      # ============================================================
      # WORKSPACES
      # ============================================================
      "$mainMod, 1, workspace, 1"
      "$mainMod, 2, workspace, 2"
      "$mainMod, 3, workspace, 3"
      "$mainMod, 4, workspace, 4"
      "$mainMod, 5, workspace, 5"
      "$mainMod, 6, workspace, 6"
      "$mainMod, 7, workspace, 7"
      "$mainMod, 8, workspace, 8"
      "$mainMod, 9, workspace, 9"
      "$mainMod, 0, workspace, 10"

      # Move to workspace
      "$mainMod SHIFT, 1, movetoworkspace, 1"
      "$mainMod SHIFT, 2, movetoworkspace, 2"
      "$mainMod SHIFT, 3, movetoworkspace, 3"
      "$mainMod SHIFT, 4, movetoworkspace, 4"
      "$mainMod SHIFT, 5, movetoworkspace, 5"
      "$mainMod SHIFT, 6, movetoworkspace, 6"
      "$mainMod SHIFT, 7, movetoworkspace, 7"
      "$mainMod SHIFT, 8, movetoworkspace, 8"
      "$mainMod SHIFT, 9, movetoworkspace, 9"
      "$mainMod SHIFT, 0, movetoworkspace, 10"

      # Workspace navigation
      "$mainMod, bracketleft, workspace, -1"
      "$mainMod, bracketright, workspace, +1"
      "$mainMod SHIFT, bracketleft, movetoworkspace, -1"
      "$mainMod SHIFT, bracketright, movetoworkspace, +1"

      # Special workspaces
      "$mainMod, U, togglespecialworkspace, scratchpad"
      "$mainMod SHIFT, U, movetoworkspace, special:scratchpad"

      # ============================================================
      # SCREENSHOTS & RECORDING
      # ============================================================
      ", Print, exec, ${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy"
      "$mainMod, Print, exec, ${pkgs.grim}/bin/grim -g \"\$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy"
      "$mainMod SHIFT, Print, exec, ${pkgs.grim}/bin/grim -g \"\$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy -t image/png"
      "$mainMod CTRL, Print, exec, ${pkgs.wf-recorder}/bin/wf-recorder -f ~/Video/screenrecord-$(date +%Y%m%d_%H%M%S).mp4"
      "$mainMod SHIFT, CTRL, R, exec, pkill -SIGINT wf-recorder"

      # ============================================================
      # WALLPAPER & APPEARANCE
      # ============================================================
      "$mainMod, W, exec, ${pkgs.waypaper}/bin/waypaper"
      "$mainMod SHIFT, W, exec, ${pkgs.swww}/bin/swww img \$(${pkgs.rofi-wayland}/bin/rofi -show file)"
      "$mainMod CTRL, W, exec, ${pkgs.hyprpicker}/bin/hyprpicker -a"

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
      "$mainMod, V, exec, ${pkgs.rofi-wayland}/bin/rofi -show emoji"
      "$mainMod, comma, exec, ${pkgs.mako}/bin/makoctl dismiss"
      "$mainMod SHIFT, comma, exec, ${pkgs.mako}/bin/makoctl dismiss -a"
      "$mainMod, period, exec, ${pkgs.mako}/bin/makoctl restore"
      "$mainMod, Tab, exec, ${pkgs.rofi-wayland}/bin/rofi -show window"
      "$mainMod SHIFT, Tab, exec, ${pkgs.rofi-wayland}/bin/rofi -show windowcd"

      # Scroll through workspaces with mouse
      "$mainMod, mouse_down, workspace, e+1"
      "$mainMod, mouse_up, workspace, e-1"
    ];

    bindl = [
      # Lock when laptop closes
      ", switch:Lid Switch, exec, ${pkgs.swaylock}/bin/swaylock -f -c $base00"
    ];

    binde = [
      # Volume keys with repeat
      ", XF86AudioRaiseVolume, exec, ${pkgs.pamixer}/bin/pamixer -i 5"
      ", XF86AudioLowerVolume, exec, ${pkgs.pamixer}/bin/pamixer -d 5"
    ];
  };
}
