# LobeHub - AI Agent Workspace
# Self-hosted AI platform for agent collaboration and multi-model management
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
in
{
  options.desktop.lobehub.enable = mkEnableOption "LobeHub AI workspace desktop application";

  config = mkIf config.desktop.lobehub.enable {
    # Add appimage-run and LobeHub wrapper
    environment.systemPackages = [
      pkgs.appimage-run
      (pkgs.writeShellScriptBin "lobehub" ''
        exec ${pkgs.appimage-run}/bin/appimage-run /home/j_kro/Downloads/LobeHub-2.1.38.AppImage "$@"
      '')
    ];
  };
}
