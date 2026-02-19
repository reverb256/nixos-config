# Hyprland Variables - Theme colors and settings
{ config, ... }:
let
  colors = config.lib.stylix.colors;
in {
  wayland.windowManager.hyprland.settings = {
    "$mainMod" = "SUPER";

    # Stylix color variables
    "$base00" = "rgb(${colors.base00_rgb})";
    "$base01" = "rgb(${colors.base01_rgb})";
    "$base02" = "rgb(${colors.base02_rgb})";
    "$base03" = "rgb(${colors.base03_rgb})";
    "$base04" = "rgb(${colors.base04_rgb})";
    "$base05" = "rgb(${colors.base05_rgb})";
    "$base06" = "rgb(${colors.base06_rgb})";
    "$base07" = "rgb(${colors.base07_rgb})";
    "$base08" = "rgb(${colors.base08_rgb})";
    "$base09" = "rgb(${colors.base09_rgb})";
    "$base0A" = "rgb(${colors.base0A_rgb})";
    "$base0B" = "rgb(${colors.base0B_rgb})";
    "$base0C" = "rgb(${colors.base0C_rgb})";
    "$base0D" = "rgb(${colors.base0D_rgb})";
    "$base0E" = "rgb(${colors.base0E_rgb})";
    "$base0F" = "rgb(${colors.base0F_rgb})";

    # Transparency
    "$alpha" = "0.8";
  };
}
