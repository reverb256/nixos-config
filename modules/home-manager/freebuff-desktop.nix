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
in
{
  # Declarative .desktop launcher for Freebuff Desktop, shown in the
  # app launcher (niri/rofi/anyrun). Follows the xdg.dataFile."applications"
  # + pkgs.makeDesktopItem pattern used by firefox-pwa-apps.nix.
  xdg.dataFile."applications/freebuff.desktop" = pkgs.makeDesktopItem {
    name = "freebuff";
    exec = "${freebuffBin} %U";
    icon = freebuffIcon;
    desktopName = "Freebuff";
    genericName = "Coding Agent Orchestrator";
    comment = "Freebuff Desktop — GitHub-native coding-agent orchestrator";
    categories = [ "Development" "Utility" ];
    startupWMClass = "Freebuff";
    terminal = false;
  };
}
