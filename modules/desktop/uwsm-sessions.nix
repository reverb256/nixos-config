# UWSM Session Integration
#
# Ensures Niri and Hyprland are properly wrapped with UWSM when launched
# from SDDM's session picker. SDDM handles session selection (Plasma,
# Niri, Hyprland, Hyprland UWSM) — one compositor at a time.
#
# NVIDIA fixes (in other modules) prevent DRM issues:
#   plasma6.nix      — kscreen-doctor gated to active VT
#   niri-settings.nix — render-drm-device, ignore-drm-device
#   hyprland.nix     — WLR_DRM_DEVICES=/dev/dri/card2
{
  lib,
  config,
  ...
}:
let
  cfg = config.desktop.uwsm-sessions.enable;
in
{
  options.desktop.uwsm-sessions = {
    enable = lib.mkEnableOption "UWSM session integration for Niri/Hyprland";
  };

  config = lib.mkIf cfg {
    # Ensure Wayland sessions are generated (no X11)
    services.xserver.enable = lib.mkDefault true;
    services.xserver.desktopManager.xterm.enable = lib.mkDefault false;
    services.xserver.windowManager.session = lib.mkForce [ ];
  };
}
