# Wayland Tools (Home Manager)
# Clipboard and screenshot utilities for Wayland compositors
{pkgs, ...}: {
  home.packages = with pkgs; [
    wl-clipboard # Wayland clipboard utilities (wl-copy, wl-paste)
    grim # Screenshot utility for Wayland
    slurp # Region selection for Wayland
    # bitwarden-desktop # TEMPORARILY DISABLED - electron-39 patch issue
    # TODO: Re-enable after nixpkgs electron-39 fix
  ];
}
