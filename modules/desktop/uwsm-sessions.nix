{
  lib,
  config,
  ...
}: let
  cfg = config.desktop.uwsm-sessions.enable;
in {
  options.desktop.uwsm-sessions = {
    enable = lib.mkEnableOption "UWSM session integration for Niri/Hyprland";
  };

  config = lib.mkIf cfg {
    services.xserver.enable = lib.mkDefault true;
    services.xserver.desktopManager.xterm.enable = lib.mkDefault false;
    services.xserver.windowManager.session = lib.mkForce [];
  };
}
