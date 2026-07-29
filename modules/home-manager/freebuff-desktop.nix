{
  config,
  pkgs,
  lib,
  ...
}: let
  # Freebuff Desktop is built from the declarative Nix package definition
  # at packages/freebuff-desktop.nix (appimageTools.wrapType2 with GPU libs).
  # We use pkgs.callPackage here because home-manager has useGlobalPkgs=false
  # and doesn't see the overlay's pkgs.freebuff-desktop directly.
  freebuff-desktop = pkgs.callPackage ../../packages/freebuff-desktop.nix {};
  freebuffBin = lib.getExe freebuff-desktop;
  freebuffIcon = "${freebuff-desktop}/share/icons/hicolor/512x512/apps/freebuff.png";

  desktopFile = pkgs.writeText "freebuff.desktop" ''
    [Desktop Entry]
    Name=Freebuff
    GenericName=Coding Agent Orchestrator
    Comment=Freebuff Desktop — GitHub-native coding-agent orchestrator
    Exec=${freebuffBin} --no-sandbox --disable-gpu-sandbox %U
    Icon=${freebuffIcon}
    Terminal=false
    Type=Application
    Categories=Development;Utility;
    StartupWMClass=Freebuff
  '';
in {
  # Declarative .desktop launcher for Freebuff Desktop, shown in the
  # app launcher (niri/rofi/anyrun).
  xdg.dataFile."applications/freebuff.desktop".source = desktopFile;

  # Ensure the declarative package is installed
  home.packages = [freebuff-desktop];
}
