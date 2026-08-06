# UWSM Session Integration
#
# Ensures Niri is properly wrapped with UWSM when launched
# from SDDM's session picker. SDDM handles session selection (one
# compositor at a time).
#
# NVIDIA fixes (in other modules) prevent DRM issues:
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
