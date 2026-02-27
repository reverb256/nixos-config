# Cursor Theme Module
# Tokyo Night Dark cursor theme configuration
{pkgs, ...}: {
  # Install cursor and icon themes
  environment.systemPackages = with pkgs; [
    # Cursor themes
    bibata-cursors
    volantes-cursors
    capitaine-cursors

    # Icon themes
    papirus-icon-theme
  ];

  # Set cursor theme
  environment.sessionVariables = {
    XCURSOR_THEME = "Bibata-Modern-Ice";
    XCURSOR_SIZE = "24";
  };

  # GTK cursor theme
  environment.variables.GTK_CURSOR_THEME = "Bibata-Modern-Ice";

  # Wayland cursor theme
  environment.variables.HYPRCURSOR_THEME = "Bibata-Modern-Ice";
  environment.variables.HYPRCURSOR_SIZE = "24";

  # Home Manager cursor theme
  # (Applied via Stylix in home.nix)
  home-manager.users.j_kro.home.pointerCursor = {
    name = "Bibata-Modern-Ice";
    package = pkgs.bibata-cursors;
    size = 24;
  };
}
