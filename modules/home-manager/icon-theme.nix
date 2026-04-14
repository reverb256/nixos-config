{ lib, pkgs, ... }:
{
  home.packages = [ pkgs.papirus-icon-theme ];

  dconf.settings."org/gnome/desktop/interface" = {
    icon-theme = "Papirus-Dark";
    cursor-theme = "Adwaita";
    cursor-size = 24;
    color-scheme = "prefer-dark";
  };

  home.sessionVariables.QT_ICON_THEME = "Papirus-Dark";
}
