{ config, pkgs, lib, ... }:

let
  # Freebuff Desktop is launched by the user-local wrapper script
  # (~/.local/bin/freebuff-desktop), which downloads/runs the
  # Freebuff-x86_64.AppImage from ~/.local/share/freebuff. The canonical
  # icon ships inside the extracted AppImage at
  # ~/.local/share/freebuff/extracted/@codebufffreebuff-desktop.png.
  # Reference it by absolute path so the launcher renders without
  # depending on hicolor icon-theme cache regeneration.
  freebuffBin = "${config.home.homeDirectory}/.local/bin/freebuff-desktop";
  freebuffIcon = "${config.home.homeDirectory}/.local/share/freebuff/extracted/@codebufffreebuff-desktop.png";

  desktopFile = pkgs.writeText "freebuff.desktop" ''
    [Desktop Entry]
    Name=Freebuff
    GenericName=Coding Agent Orchestrator
    Comment=Freebuff Desktop — GitHub-native coding-agent orchestrator
    Exec=${freebuffBin} %U
    Icon=${freebuffIcon}
    Terminal=false
    Type=Application
    Categories=Development;Utility;
    StartupWMClass=Freebuff
  '';
in
{
  # Declarative .desktop launcher for Freebuff Desktop, shown in the
  # app launcher (niri/rofi/anyrun). Written as plain text via xdg.dataFile
  # (not pkgs.makeDesktopItem) to avoid the __ignoreNulls attribute that the
  # current home-manager version no longer accepts.
  xdg.dataFile."applications/freebuff.desktop".source = desktopFile;
}
