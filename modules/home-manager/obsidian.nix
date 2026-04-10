# Obsidian - Second Brain Knowledge Base
# Local-first, markdown-based knowledge management with plugin ecosystem
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    obsidian
  ];

  # Obsidian desktop file for mime associations
  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/obsidian" = [ "obsidian.desktop" ];
  };
}
