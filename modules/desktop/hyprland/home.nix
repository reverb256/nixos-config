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
    settings = { };

    # System-wide startup applications
    systemdIntegration = true;
  };

  # Home Manager packages for Hyprland
  home.packages = with pkgs; [
    waybar
    rofi-wayland
    mako
    swaylock
    swaylock-effects
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
