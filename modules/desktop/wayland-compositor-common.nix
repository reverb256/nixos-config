# Wayland Compositor Shared Resources
# Packages and configuration shared across all Wayland compositors (Niri, Hyprland).
# Noctalia-shell auto-detects the running compositor at runtime via env vars
# (NIRI_SOCKET, HYPRLAND_INSTANCE_SIGNATURE, etc.) and loads the correct backend.
#
# This module installs when ANY compositor is enabled to avoid duplication.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  niriEnabled = config.programs.niri.enable or false;
  hyprlandEnabled = config.programs.hyprland.enable or false;
  anyCompositor = niriEnabled || hyprlandEnabled;
in
{
  config = lib.mkIf anyCompositor {
    environment.systemPackages = [
      # Desktop shell — auto-detects compositor, single package serves all
      # Replaces: waybar, mako, fuzzel, wofi, swaybg, etc.
      pkgs.noctalia-shell

      # Clipboard manager (noctalia clipboard integration)
      pkgs.cliphist

      # Screen recording
      pkgs.wf-recorder

      # Cursor theme (matches Adwaita in compositor settings)
      pkgs.adwaita-icon-theme
    ];

    # Shared services needed by both compositors
    services.gnome.gnome-keyring.enable = lib.mkDefault true;
    services.gnome.gcr-ssh-agent.enable = lib.mkDefault false;
  };
}
