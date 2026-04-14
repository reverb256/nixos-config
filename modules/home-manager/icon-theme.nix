# Icon Theme Configuration
# Sets Papirus-Dark as the icon theme for Noctalia launcher and all apps.
#
# Why dconf instead of gtk.enable:
# The Plasma 6 module (still imported globally) claims the gtk.enable namespace,
# forcing it to false. HM's gtk module then blocks xdg.configFile and home.file
# from writing to GTK paths. dconf is the runtime source of truth that GTK reads,
# so it's the one that actually matters.
{ lib, pkgs, ... }:
{
  # Install the icon theme package (provides actual icon files)
  home.packages = [ pkgs.papirus-icon-theme ];

  # dconf is what GTK apps actually read at runtime
  dconf.settings."org/gnome/desktop/interface" = {
    icon-theme = "Papirus-Dark";
    cursor-theme = "Adwaita";
    cursor-size = 24;
    color-scheme = "prefer-dark";
  };

  # Qt icon theme sync
  home.sessionVariables.QT_ICON_THEME = "Papirus-Dark";
}
