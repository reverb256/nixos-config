# Hyprland Home Manager Configuration
# Modular configuration for Hyprland Wayland compositor
{ config, lib, pkgs, ... }:
let
  cfg = config.wayland.windowManager.hyprland;
in {
  imports = [
    ./settings.nix
    ./binds.nix
    ./windowrules.nix
    ./variables.nix
  ];

  # Enable Hyprland
  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    # Extra config will be merged from the imported modules above
    settings = {
      # Override any conflicting default settings
      general = lib.mkOverride 1000 {
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
    };

    # System-wide startup applications (using new systemd.enable option)
    systemd.enable = true;
  };

  # Home Manager packages for Hyprland
  home.packages = with pkgs; [
    waybar
    rofi
    mako
    swaylock-effects # includes swaylock with effects/blur support
    hyprlock
    wlogout
    waypaper
    swww
    grim
    slurp
    wl-clipboard
    wf-recorder
    wl-mirror
    hyprpicker
    xdg-desktop-portal-hyprland
  ];
}
