# Icons Theme Module
# Tokyo Night Dark themed icons
{pkgs, ...}: {
  # Install icon themes
  environment.systemPackages = with pkgs; [
    papirus-icon-theme
    colloid-icon-theme
    numix-icon-theme-circle
  ];

  # Set default icon theme (via Stylix)
  # Stylix handles GTK icon theming automatically

  # ============================================================================
  # ICON THEMES
  # ============================================================================
  #
  # **Tokyo Night Extras:**
  # - Matches Tokyo Night Dark color scheme
  # - Comprehensive icon set
  #
  # **Papirus:**
  # - Feature-rich icon theme
  # - Multiple color variants
  #
  # **Colloid:**
  # - Modern, clean design
  # - Teal variant to match Tokyo Night
  #
  # **Numix Circle:**
  # - Circle-shaped icons
  # - Clean and minimal
  #
  # ============================================================================
}
