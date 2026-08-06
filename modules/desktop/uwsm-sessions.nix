# UWSM Session Integration
#
# Ensures Niri is properly wrapped with UWSM when launched
# from SDDM's session picker. SDDM handles session selection (one
# compositor at a time).
#
# NVIDIA fixes (in other modules) prevent DRM issues:
#   desktop-monitor.nix — kscreen-doctor gated to active VT
#   (niri-settings.nix removed — render-drm-device/ignore-drm-device now live in
#    home-manager-config/modules/niri-config.nix via programs.niri.settings)
#   desktop-monitor.nix — systemd GPU readiness before display-manager
{
  lib,
  config,
  ...
}: let
  cfg = config.desktop.uwsm-sessions.enable;
in {
  options.desktop.uwsm-sessions = {
    enable = lib.mkEnableOption "UWSM session integration for Niri";
  };

  config = lib.mkIf cfg {
    # Ensure Wayland sessions are generated (no X11)
    services.xserver.enable = lib.mkDefault true;
    services.xserver.desktopManager.xterm.enable = lib.mkDefault false;
    services.xserver.windowManager.session = lib.mkForce [];
  };
}
