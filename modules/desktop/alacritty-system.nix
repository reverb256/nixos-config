{
  lib,
  pkgs,
  config,
  ...
}:
# System-level Alacritty package for hosts running Niri.
#
# Long-lived GUI applications are launched through UWSM from the Home Manager
# Niri bindings. Keep this module limited to making the terminal package
# available to the system generation; resource limits belong in explicit
# systemd units only when measurements justify them.
let
  niriEnabled = config.programs.niri.enable or false;
in
  lib.mkIf niriEnabled {
    environment.systemPackages = with pkgs; [
      # The terminal itself.
      alacritty

    ];
  }
