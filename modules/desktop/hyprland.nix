# Hyprland Module
# Wayland compositor with Noctalia shell ecosystem
# Can be used alongside Plasma 6 - choose in display manager
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.hyprland.enable;
in
{
  programs.hyprland = {
    enable = lib.mkDefault false;
    # UWSM provides: session management, auto-restart on crash, proper env setup
    # This is the ONLY session we want — disable the raw hyprland.desktop
    withUWSM = true;
  };

  # Only install ecosystem packages when Hyprland is enabled
  config = lib.mkIf cfg {
    programs.hyprlock.enable = true;

    environment.systemPackages = with pkgs; [
      # Desktop shell (bar, notifications, launcher, dock, wallpapers)
      noctalia-shell

      # Core Hyprland tools
      hyprpicker # Color picker
      hyprcursor # Custom cursor support
      hyprlock # Screen locker
      hyprsunset # Blue light filter
      hyprpolkitagent # Polkit agent for Hyprland

      # Wayland utilities
      wayvnc # VNC server for Wayland

      # Cursor theme
      adwaita-icon-theme
    ];

    # Remove the raw hyprland.desktop — UWSM session is the only one we want
    environment.pathsToLink = lib.mkForce [ "/share/wayland-sessions" ];
  };

  # NOTES:
  # SDDM sessions after this module:
  #   - Plasma (Wayland) — plasma.desktop
  #   - Hyprland (UWSM) — hyprland-uwsm.desktop
  #   - Niri — niri (from niri.nix)
  # X11 Plasma (plasmax11.desktop) is disabled in desktop.nix
}
