# Hyprland Variables - Theme colors and settings
{ config, lib, ... }:
let
  colors = config.lib.stylix.colors;

  # Convert hex color to rgb(r,g,b) format for Hyprland
  hexToRgb = hex: let
    r = lib.substring 1 2 hex;
    g = lib.substring 3 2 hex;
    b = lib.substring 5 2 hex;
  in "rgb(${r},${g},${b})";
in {
  wayland.windowManager.hyprland.settings = {
    "$mainMod" = "SUPER";

    # Stylix color variables (converted to RGB for Hyprland)
    "$base00" = hexToRgb colors.base00;
    "$base01" = hexToRgb colors.base01;
    "$base02" = hexToRgb colors.base02;
    "$base03" = hexToRgb colors.base03;
    "$base04" = hexToRgb colors.base04;
    "$base05" = hexToRgb colors.base05;
    "$base06" = hexToRgb colors.base06;
    "$base07" = hexToRgb colors.base07;
    "$base08" = hexToRgb colors.base08;
    "$base09" = hexToRgb colors.base09;
    "$base0A" = hexToRgb colors.base0A;
    "$base0B" = hexToRgb colors.base0B;
    "$base0C" = hexToRgb colors.base0C;
    "$base0D" = hexToRgb colors.base0D;
    "$base0E" = hexToRgb colors.base0E;
    "$base0F" = hexToRgb colors.base0F;

    # Transparency
    "$alpha" = "0.8";
  };
}
