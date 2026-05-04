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
        "HDMI-A-2,3840x2160@60,10000x0,1.5"
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
        "XCURSOR_THEME,Adwaita"
        "XCURSOR_SIZE,24"
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
        gaps_in = 8;
        gaps_out = 8;
        border_size = 2;
        layout = "dwindle";
      };

      dwindle = {
        preserve_split = true;
        smart_resizing = true;
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
      };

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
          scroll_method = "twofinger";
          middle_button_emulation = false;
        };
      };

      bind =
        [
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
          "SUPER, G, exec, launch-or-focus Discord uwsm app -- discord"
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
          "SUPER, Comma, exec, noctalia-shell ipc call notifications dismissLast"
          "SUPER ALT, Space, exec, noctalia-shell ipc call settings toggle"
          "SUPER SHIFT, Space, exec, noctalia-shell ipc call bar toggle"
          "SUPER CTRL, A, exec, noctalia-shell ipc call volume togglePanel"
          "SUPER CTRL, W, exec, noctalia-shell ipc call network togglePanel"
          "SUPER CTRL, B, exec, noctalia-shell ipc call bluetooth togglePanel"
          "SUPER CTRL, I, exec, noctalia-shell ipc call idleInhibitor toggle"
          "SUPER CTRL, N, exec, noctalia-shell ipc call nightLight toggle"
          "SUPER CTRL, D, exec, noctalia-shell ipc call darkMode toggle"
          "SUPER CTRL, T, exec, noctalia-shell ipc call systemMonitor toggle"
          "SUPER CTRL, S, exec, noctalia-shell ipc call share toggle"
          "SUPER CTRL, L, exec, noctalia-shell ipc call lockScreen lock"
          "SUPER CTRL, O, exec, noctalia-shell ipc call controlCenter toggle"
          "SUPER CTRL SHIFT, W, exec, noctalia-shell ipc call wallpaper random"
          "SUPER SHIFT, Comma, exec, noctalia-shell ipc call notifications dismissAll"
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
          "SUPER, Period, togglesplit"
          "SUPER CTRL, Period, movewindow, silentspace"
          "SUPER, R, splitratio, exact 0.5"
          "SUPER SHIFT, R, splitratio, exact 0.7"
          "SUPER, Minus, resizeactive, -5% 0"
          "SUPER, Equal, resizeactive, 5% 0"
          "SUPER SHIFT, Minus, resizeactive, 0 -5%"
          "SUPER SHIFT, Equal, resizeactive, 0 5%"
          "SUPER, C, centerwindow"
          "SUPER, Home, movefocus, l"
          "SUPER, End, movefocus, r"
          "SUPER SHIFT, Home, movewindow, l"
          "SUPER SHIFT, End, movewindow, r"
          "SUPER, F, fullscreen, 0"
          "SUPER SHIFT, F, fullscreen, 1"

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
          "SUPER SHIFT, Print, exec, screenshot fullscreen"
          "SUPER ALT, Print, exec, screenshot window"
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

      windowrule =
        [
          # Floating — system dialogs
          "float, match:class ^(pavucontrol)$"
          "float, match:class ^(nm-connection-editor)$"
          "float, match:class ^(blueman-manager)$"
          "float, match:class ^(gnome-calculator)$"
          "float, match:class ^(gnome-control-center)$"
          "float, match:class ^(org.kde.kinfocenter)$"
          "float, match:class ^(file-roller)$"
          "float, match:class ^(org.kde.ark)$"
          "float, match:class ^(pinentry-)"
          "float, match:title ^(File Transfer)"
          "float, match:title ^(Authentication)"

          # Polkit auth
          "float, match:class ^(org.kde.polkit-kde-authentication-agent-1)$"
          "float, match:title ^(.*Authentication Required)"

          # File choosers — floating + fixed size
          "float, match:title ^(Open (.*Files?|Folder))"
          "float, match:title ^(Save (.*Files?|As))"
          "float, match:title ^(Select)"
          "float, match:title ^(Choose)"
          "float, match:title ^(Rename)"
          "float, match:title ^(Properties)"
          "size 900 600, match:title ^(Open (.*Files?|Folder))"
          "size 900 600, match:title ^(Save (.*Files?|As))"
          "float, match:class ^(org.kde.dolphin)$, match:title ^(Open)"
          "float, match:class ^(org.kde.dolphin)$, match:title ^(Save)"
          "float, match:class ^(org.kde.dolphin)$, match:title ^(Copy)"
          "float, match:class ^(org.kde.dolphin)$, match:title ^(Move)"
          "float, match:class ^(org.kde.dolphin)$, match:title ^(Delete)"
          "float, match:class ^(org.gtk.FileChooserDialog)$"
          "float, match:class ^(xdg-desktop-portal-gtk)$"

          # Screen share picker
          "float, match:title ^(Choose what to share)"

          # PiP overlay
          "float, match:title ^(Picture-in-Picture)"
          "move 10 10, match:title ^(Picture-in-Picture)"
          "size 400 225, match:title ^(Picture-in-Picture)"

          # Steam notification toasts — top-right
          "float, match:class ^(steam)$, match:title ^(notificationtoasts)"
          "move 100%-10-10 10, match:class ^(steam)$, match:title ^(notificationtoasts)"

          # Gaming — route to HDMI-A-2
          "monitor HDMI-A-2, match:class ^(.*GenshinImpact.*)"
          "fullscreen, match:class ^(.*GenshinImpact.*)"
          "monitor HDMI-A-2, match:class ^(steam)$, match:title ^(Steam)$"
          "fullscreen, match:class ^(steam)$, match:title ^(Steam)$"
          "monitor HDMI-A-2, match:class ^(moe.launcher.an-anime-game-launcher)$"
          "monitor HDMI-A-2, match:class ^(moe.launcher.the-honkers-railway-launcher)$"
          "monitor HDMI-A-2, match:class ^(lutris)$"
          "monitor HDMI-A-2, match:class ^(heroic)$"
          "monitor HDMI-A-2, match:class ^(minecraft)$"
          "monitor HDMI-A-2, match:class ^(prism-launcher)$"
          "monitor HDMI-A-2, match:class ^(com.libretro.RetroArch)$"
          "monitor HDMI-A-2, match:class ^(com.moonlight_stream.Moonlight)$"

          # Steam popup dialogs — maximize
          "maximize, match:class ^(steam)$, match:title ^(Settings)$"
          "maximize, match:class ^(steam)$, match:title ^(Friends)$"
          "maximize, match:class ^(steam)$, match:title ^(Chat)$"
          "maximize, match:class ^(steam)$, match:title ^(Properties)"
          "maximize, match:class ^(steam)$, match:title ^(Steam Guard)"
          "maximize, match:class ^(steam)$, match:title ^(Screenshot)"

          # CopyQ
          "float, match:class ^(copyq)$"
        ];
    };
  };
}
