{
  pkgs,
  lib,
  config,
  ...
}: let
  opacity = config.stylix.opacity;
in {
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = true;
    xwayland.enable = true;

    settings = {
      monitor = [
        "DP-5,1920x1080@144,0x349,1"
        "DP-4,1920x1080@75,1920x0,1"
        "DP-6,1600x900@60,1920x1080,1"
        "HDMI-A-2,3840x2160@60,10000x0,1.5,bitdepth,10,cm,hdr,sdrbrightness,1.3,sdrsaturation,1.0"
      ];

      workspace = [
        "1,monitor:DP-5,default:true"
        "2,monitor:DP-5,persistent:true"
        "3,monitor:DP-5,persistent:true"
        "4,monitor:DP-5,persistent:true"
        "5,monitor:DP-4,default:true"
        "6,monitor:DP-4,persistent:true"
        "7,monitor:DP-6,default:true"
        "8,monitor:DP-6,persistent:true"
        "9,monitor:HDMI-A-2,default:true"
        "10,monitor:HDMI-A-2,persistent:true"
      ];

      env = [
        "XCURSOR_THEME,${config.stylix.cursor.name}"
        "XCURSOR_SIZE,${toString config.stylix.cursor.size}"
        "HYPRCURSOR_THEME,${config.stylix.cursor.name}"
        "HYPRCURSOR_SIZE,${toString config.stylix.cursor.size}"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
        "NIXOS_OZONE_WL,1"
        "MOZ_ENABLE_WAYLAND,1"
        "QT_QPA_PLATFORM,wayland;xcb"
        "QT_AUTO_SCREEN_SCALE_FACTOR,1"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
      ];

      "exec-once" = [
        "uwsm finalize"
        "uwsm app -s s -- ${lib.getExe' pkgs.polkit_gnome "polkit-gnome-authentication-agent-1"}"
        "uwsm app -s s -- noctalia-shell"
        "uwsm app -s b -- ckb-next -b"
      ];

      general = {
        gaps_in = 0;
        gaps_out = 8;
        border_size = 2;
        layout = "scrolling";
      };

      scrolling = {
        fullscreen_on_one_column = true;
        column_width = 0.5;
        focus_fit_method = 1;
        follow_focus = true;
        follow_min_visible = 0.4;
        explicit_column_widths = "0.333,0.5,0.667,1.0";
        direction = "right";
      };

      decoration = {
        rounding = 0;
        blur.enabled = false;
        active_opacity = opacity.applications;
        inactive_opacity = opacity.applications;
        fullscreen_opacity = opacity.applications;
      };

      cursor = {
        inactive_timeout = 3;
        hide_on_key_press = true;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        middle_click_paste = false;
      };

      "general:allow_tearing" = false;

      input = {
        kb_layout = "us";
        repeat_rate = 50;
        repeat_delay = 300;
        numlock_by_default = true;
        follow_mouse = 1;
        sensitivity = 0;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
          disable_while_typing = true;
          clickfinger_behavior = true;
          middle_button_emulation = false;
        };
      };

      bind = [
        # Apps
        "SUPER, Return, exec, uwsm app -- alacritty"
        "SUPER, B, exec, launch-or-focus Zen uwsm app -- zen-twilight"
        "SUPER SHIFT, B, exec, uwsm app -- zen-twilight --private-window"
        "SUPER, E, exec, launch-or-focus Dolphin ${lib.getExe pkgs.kdePackages.dolphin}"
        "SUPER, N, exec, launch-or-focus KWrite uwsm app -- ${lib.getExe' pkgs.kdePackages.kate "kwrite"}"
        "SUPER SHIFT, N, exec, launch-or-focus Kate uwsm app -- ${lib.getExe pkgs.kdePackages.kate}"
        "SUPER, O, exec, launch-or-focus Obsidian uwsm app -- obsidian"
        "SUPER, T, exec, uwsm app -- alacritty -e btop"
        "SUPER, D, exec, uwsm app -- alacritty -e lazydocker"
        "SUPER, G, exec, launch-or-focus Discord uwsm app -- vesktop"
        "SUPER SHIFT, G, exec, launch-or-focus Grok uwsm app -- firefoxpwa site launch grok"
        "SUPER, A, exec, launch-or-focus LM uwsm app -- lm-studio"
        "SUPER SHIFT, A, exec, launch-or-focus ChatGPT uwsm app -- firefoxpwa site launch chatgpt"
        "SUPER, M, exec, launch-or-focus Spotify uwsm app -- flatpak run com.spotify.Client"
        "SUPER SHIFT, M, exec, launch-or-focus Caprine uwsm app -- caprine"
        "SUPER, Slash, exec, launch-or-focus Bitwarden uwsm app -- flatpak run com.bitwarden.desktop"

        # Noctalia shell IPC
        "SUPER, Space, exec, noctalia-shell ipc call launcher toggle"
        "SUPER CTRL, V, exec, noctalia-shell ipc call launcher clipboard"
        "SUPER CTRL, E, exec, noctalia-shell ipc call launcher emoji"
        "SUPER CTRL, Slash, exec, noctalia-shell ipc call launcher command"
        "SUPER SHIFT, Slash, exec, noctalia-shell ipc call launcher windows"
        "SUPER CTRL SHIFT, Comma, exec, noctalia-shell ipc call notifications dismissLast"
        "SUPER ALT SHIFT, N, exec, noctalia-shell ipc call notifications dismissAll"
        "SUPER CTRL, Comma, exec, noctalia-shell ipc call notifications toggleDND"
        "SUPER ALT, Comma, exec, noctalia-shell ipc call notifications toggleHistory"
        "SUPER ALT SHIFT, Comma, exec, noctalia-shell ipc call notifications invokeDefault"

        # Scratchpad & misc
        "SUPER, S, exec, scratchpad-toggle"
        "SUPER ALT, V, exec, voxtype record toggle"
        "SUPER, V, exec, uwsm app -- copyq show"
        "SUPER SHIFT, V, togglefloating"

        # Window management
        "SUPER, Q, killactive"
        "ALT, Tab, cyclenext"
        "SUPER, Left, movefocus, l"
        "SUPER, Right, movefocus, r"
        "SUPER, Up, movefocus, u"
        "SUPER, Down, movefocus, d"
        "SUPER SHIFT, Left, movewindow, l"
        "SUPER SHIFT, Right, movewindow, r"
        "SUPER SHIFT, Up, movewindow, u"
        "SUPER SHIFT, Down, movewindow, d"

        # Scrolling column navigation
        "SUPER, Period, layoutmsg, move +col"
        "SUPER, Comma, layoutmsg, move -col"
        "SUPER CTRL, Period, movetoworkspacesilent, e+1"
        "SUPER, R, layoutmsg, colresize +conf"
        "SUPER SHIFT, R, layoutmsg, colresize -conf"
        "SUPER, Minus, layoutmsg, colresize -0.1"
        "SUPER, Equal, layoutmsg, colresize +0.1"
        "SUPER SHIFT, Minus, layoutmsg, resizeactive, 0 -5%"
        "SUPER SHIFT, Equal, layoutmsg, resizeactive, 0 5%"
        "SUPER, C, centerwindow"
        "SUPER, Home, movefocus, l"
        "SUPER, End, movefocus, r"
        "SUPER SHIFT, Home, movewindow, l"
        "SUPER SHIFT, End, movewindow, r"
        "SUPER, F, fullscreen, 0"
        "SUPER SHIFT, F, fullscreen, 1"
        "SUPER, P, layoutmsg, promote"
        "SUPER SHIFT, Comma, layoutmsg, swapcol l"
        "SUPER SHIFT, Period, layoutmsg, swapcol r"

        # Workspaces
        "SUPER, 1, workspace, 1"
        "SUPER, 2, workspace, 2"
        "SUPER, 3, workspace, 3"
        "SUPER, 4, workspace, 4"
        "SUPER, 5, workspace, 5"
        "SUPER, 6, workspace, 6"
        "SUPER, 7, workspace, 7"
        "SUPER, 8, workspace, 8"
        "SUPER, 9, workspace, 9"
        "SUPER, 0, workspace, 10"
        "SUPER SHIFT, 1, movetoworkspace, 1"
        "SUPER SHIFT, 2, movetoworkspace, 2"
        "SUPER SHIFT, 3, movetoworkspace, 3"
        "SUPER SHIFT, 4, movetoworkspace, 4"
        "SUPER SHIFT, 5, movetoworkspace, 5"
        "SUPER SHIFT, 6, movetoworkspace, 6"
        "SUPER SHIFT, 7, movetoworkspace, 7"
        "SUPER SHIFT, 8, movetoworkspace, 8"
        "SUPER SHIFT, 9, movetoworkspace, 9"
        "SUPER SHIFT, 0, movetoworkspace, 10"
        "SUPER, Page_Down, workspace, e+1"
        "SUPER, Page_Up, workspace, e-1"
        "SUPER SHIFT, Page_Down, movetoworkspace, e+1"
        "SUPER SHIFT, Page_Up, movetoworkspace, e-1"
        "SUPER, Tab, workspace, e+1"
        "SUPER SHIFT, Tab, workspace, e-1"
        "SUPER CTRL, Tab, workspace, previous"

        # Monitor navigation
        "SUPER CTRL, Left, focusmonitor, l"
        "SUPER CTRL, Right, focusmonitor, r"
        "SUPER CTRL, Up, focusmonitor, u"
        "SUPER CTRL, Down, focusmonitor, d"
        "SUPER CTRL SHIFT, Left, movewindow, mon:l"
        "SUPER CTRL SHIFT, Right, movewindow, mon:r"
        "SUPER CTRL SHIFT, Up, movewindow, mon:u"
        "SUPER CTRL SHIFT, Down, movewindow, mon:d"
        "SUPER SHIFT ALT, Left, movecurrentworkspacetomonitor, l"
        "SUPER SHIFT ALT, Right, movecurrentworkspacetomonitor, r"
        "SUPER SHIFT ALT, Up, movecurrentworkspacetomonitor, u"
        "SUPER SHIFT ALT, Down, movecurrentworkspacetomonitor, d"

        # Screenshots
        ", Print, exec, screenshot region"
        "SUPER, Print, exec, screenshot color"
        "SUPER CTRL, Print, exec, ocr-extract"
        "SUPER SHIFT, Print, exec, screenshot fullscreen"
        "SUPER ALT, Print, exec, screenshot window"
        "SUPER CTRL SHIFT, Print, exec, grim -o $(hyprctl monitors -j | ${lib.getExe pkgs.jq} -r '.[] | select(.focused) | .name') ~/Pictures/Screenshots/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"
        "ALT, Print, exec, screenrecord"
        "SUPER ALT SHIFT, Print, exec, screenrecord desktop"

        # Session
        "SUPER, Escape, exec, noctalia-shell ipc call sessionMenu toggle"
        "SUPER CTRL, Escape, exec, systemctl suspend"
        "SUPER SHIFT, Escape, exit"
        "SUPER SHIFT, C, exec, hyprctl reload"
        "CTRL ALT, Delete, exec, hyprctl clients -j | ${lib.getExe pkgs.jq} -r '.[].address' | xargs -I{} hyprctl dispatch closewindow address:{}"
      ];

      bindl = [
        ", XF86AudioPlay, exec, noctalia-shell ipc call media playPause"
        ", XF86AudioNext, exec, noctalia-shell ipc call media next"
        ", XF86AudioPrev, exec, noctalia-shell ipc call media previous"
        ", XF86AudioStop, exec, noctalia-shell ipc call media stop"
        ", XF86AudioMute, exec, noctalia-shell ipc call volume muteOutput"
        ", XF86AudioMicMute, exec, noctalia-shell ipc call volume muteInput"
      ];

      bindel = [
        ", XF86AudioRaiseVolume, exec, noctalia-shell ipc call volume increase"
        ", XF86AudioLowerVolume, exec, noctalia-shell ipc call volume decrease"
      ];

      bindm = [
        "SUPER, mouse:272, movewindow"
        "SUPER, mouse:273, resizewindow"
      ];

      windowrule = [
        # Floating — system dialogs
        "float class:^(pavucontrol)$"
        "float class:^(nm-connection-editor)$"
        "float class:^(blueman-manager)$"
        "float class:^(gnome-calculator)$"
        "float class:^(gnome-control-center)$"
        "float class:^(org.kde.kinfocenter)$"
        "float class:^(file-roller)$"
        "float class:^(org.kde.ark)$"
        "float class:^(pinentry-)"
        "float title:^(File Transfer)"
        "float title:^(Authentication)"

        # Polkit auth
        "float class:^(org.kde.polkit-kde-authentication-agent-1)$"
        "float title:^(.*Authentication Required)"

        # File choosers — floating + fixed size
        "float title:^(Open (.*Files?|Folder))"
        "float title:^(Save (.*Files?|As))"
        "float title:^(Select)"
        "float title:^(Choose)"
        "float title:^(Rename)"
        "float title:^(Properties)"
        "size 900 600 title:^(Open (.*Files?|Folder))"
        "size 900 600 title:^(Save (.*Files?|As))"
        "float class:^(org.kde.dolphin)$ title:^(Open)"
        "float class:^(org.kde.dolphin)$ title:^(Save)"
        "float class:^(org.kde.dolphin)$ title:^(Copy)"
        "float class:^(org.kde.dolphin)$ title:^(Move)"
        "float class:^(org.kde.dolphin)$ title:^(Delete)"
        "float class:^(org.gtk.FileChooserDialog)$"
        "float class:^(xdg-desktop-portal-gtk)$"

        # Screen share picker
        "float title:^(Choose what to share)"

        # PiP overlay
        "float title:^(Picture-in-Picture)"
        "move 10 10 title:^(Picture-in-Picture)"
        "size 400 225 title:^(Picture-in-Picture)"

        # Steam notification toasts — top-right
        "float class:^(steam)$ title:^(notificationtoasts)"
        "move 100%-10-10 10 class:^(steam)$ title:^(notificationtoasts)"

        # Gaming — route to HDMI-A-2
        "monitor HDMI-A-2 class:^(.*GenshinImpact.*)"
        "fullscreen class:^(.*GenshinImpact.*)"
        "monitor HDMI-A-2 class:^(steam)$ title:^(Steam)$"
        "fullscreen class:^(steam)$ title:^(Steam)$"
        "monitor HDMI-A-2 class:^(moe.launcher.an-anime-game-launcher)$"
        "monitor HDMI-A-2 class:^(moe.launcher.the-honkers-railway-launcher)$"
        "monitor HDMI-A-2 class:^(lutris)$"
        "monitor HDMI-A-2 class:^(heroic)$"
        "monitor HDMI-A-2 class:^(minecraft)$"
        "monitor HDMI-A-2 class:^(prism-launcher)$"
        "monitor HDMI-A-2 class:^(com.libretro.RetroArch)$"
        "monitor HDMI-A-2 class:^(com.moonlight_stream.Moonlight)$"

        # Steam popup dialogs — maximize
        "maximize class:^(steam)$ title:^(Settings)$"
        "maximize class:^(steam)$ title:^(Friends)$"
        "maximize class:^(steam)$ title:^(Chat)$"
        "maximize class:^(steam)$ title:^(Properties)"
        "maximize class:^(steam)$ title:^(Steam Guard)"
        "maximize class:^(steam)$ title:^(Screenshot)"

        # CopyQ
        "float class:^(copyq)$"

        # Spotify — no decorations (fixes CSD issues)
        "rounding 0 class:^(spotify)$"
      ];
    };
  };
}
