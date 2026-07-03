{ pkgs, ... }: {
  # Icon theme is now set by Stylix (stylix.iconTheme) — handles GTK, dconf, and Qt.
  # This module only ensures the icon pack is installed for apps that read it directly.
  home.packages = [pkgs.papirus-icon-theme];
}
