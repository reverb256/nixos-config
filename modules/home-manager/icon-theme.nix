{
  lib,
  pkgs,
  ...
}: {
  home.packages = [pkgs.papirus-icon-theme];

  dconf.settings."org/gnome/desktop/interface" = {
    icon-theme = "Papirus-Dark";
    color-scheme = "prefer-dark";
  };

  home.sessionVariables.QT_ICON_THEME = "Papirus-Dark";
}
