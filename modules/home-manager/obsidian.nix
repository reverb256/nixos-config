{ pkgs, ... }:
{
  home.packages = with pkgs; [
    obsidian
  ];

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/obsidian" = [ "obsidian.desktop" ];
  };
}
