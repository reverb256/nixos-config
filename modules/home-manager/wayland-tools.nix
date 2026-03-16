# Wayland Tools (Home Manager)
# Clipboard and screenshot utilities for Wayland compositors
{pkgs, ...}: {
  home.packages = with pkgs; [
    wl-clipboard # Wayland clipboard utilities (wl-copy, wl-paste)
    grim # Screenshot utility for Wayland
    slurp # Region selection for Wayland
    bitwarden-desktop # Password manager desktop app (includes native messaging for Zen)
  ];
}
