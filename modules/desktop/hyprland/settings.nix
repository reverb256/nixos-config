# Hyprland Settings - Core configuration
{ ... }:
{
  wayland.windowManager.hyprland.settings = {
    input = {
      kb_layout = "us";
      numlock_by_default = true;
      repeat_delay = 300;
      repeat_rate = 50;
      follow_mouse = 1;
      float_switch_override_focus = 1;
      sensitivity = 0.0;
      touchpad = {
        natural_scroll = true;
        disable_while_typing = true;
        tap-to-click = true;
      };
    };

    general = {
      gaps_in = 5;
      gaps_out = 10;
      border_size = 2;
      "col.active_border" = "rgba($base0Dff) rgba($base0Fff) 45deg";
      "col.inactive_border" = "rgba($base0080)";
      layout = "dwindle";
      resize_on_border = true;
      extend_border_grab_area = 15;
      hover_icon_on_border = true;
    };

    dwindle = {
      pseudotile = true;
      preserve_split = true;
      force_split = 2;
      special_scale_factor = 1.0;
      split_width_multiplier = 1.0;
    };

    master = {
      new_status = "master";
      new_on_top = false;
      special_scale_factor = 1.0;
      no_gaps_when_only = false;
    };

    misc = {
      force_default_wallpaper = 0;
      disable_hyprland_logo = true;
      always_follow_on_dnd = true;
      layers_hog_keyboard_focus = true;
      animate_manual_resizes = true;
      enable_swallow = true;
      focus_on_activate = true;
      middle_click_paste = false;
      vfr = true;
      vrr = 0;
      mouse_move_enables_dpms = true;
      key_press_enables_dpms = true;
      no_direct_scanout = false;
    };

    decoration = {
      rounding = 8;
      multisample_edges = true;
      active_opacity = 1.0;
      inactive_opacity = 0.9;
      fullscreen_opacity = 1.0;
      drop_shadow = true;
      shadow_range = 4;
      shadow_render_power = 3;
      "col.shadow" = "rgba($base0055)";
      "col.shadow_inactive" = "rgba($base0033)";

      blur = {
        enabled = true;
        size = 5;
        passes = 3;
        brightness = 1.0;
        contrast = 1.2;
        noise = 0.0;
        ignore_opacity = false;
        new_optimizations = true;
        xray = true;
      };
    };

    animations = {
      enabled = true;

      bezier = [
        "easeOutCubic, 0.33, 1, 0.68, 1"
        "easeInOutCubic, 0.65, 0, 0.35, 1"
        "linear, 0, 0, 1, 1"
        "easeOutQuint, 0.22, 1, 0.36, 1"
      ];

      animation = [
        "windows, 1, 3, easeOutCubic, slide"
        "windowsOut, 1, 3, easeInOutCubic, fade"
        "windowsMove, 1, 3, easeOutCubic"
        "fadeIn, 1, 3, easeOutQuint"
        "fadeOut, 1, 3, easeOutQuint"
        "workspaces, 1, 4, easeOutCubic, slide"
        "workspacesIn, 1, 4, easeOutCubic, slide"
        "workspacesOut, 1, 4, easeOutCubic, slide"
        "specialWorkspace, 1, 3, easeOutCubic, slidevert"
        "border, 1, 2.7, easeOutCubic"
        "borderangle, 1, 30, easeInOutCubic, once"
      ];
    };

    xwayland = {
      force_zero_scaling = true;
    };
  };
}
