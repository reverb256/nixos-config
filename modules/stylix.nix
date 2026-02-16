# Stylix - Declarative Theming for NixOS
# Uses base16 color schemes for system-wide theming
{pkgs, config, ...}: let
  cfg = config.stylix;
in {
  options.stylix = {
    enable = pkgs.lib.mkEnableOption "Stylix system-wide theming";
  };

  config = pkgs.lib.mkIf cfg.enable {
    # Base16 color scheme - Catppuccin Mocha (dark theme)
    stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

    # Image-based wallpaper (optional - can be changed per-host)
    # stylix.image = /path/to/wallpaper.png;

    # Polarity - auto-detect from base16 scheme
    stylix.polarity = "dark";

    # Cursor configuration
    stylix.cursor = {
      name = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
      size = 24;
    };

    # Font configuration
    stylix.fonts = {
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };
      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
      };
      monospace = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans Mono";
      };
      emoji = {
        package = pkgs.noto-fonts-emoji;
        name = "Noto Color Emoji";
      };
    };

    # Target-specific theming
    stylix.targets = {
      # Desktop environment
      plasma = {
        enable = true;
      };
      # Terminal emulators
      kitty = {
        enable = false; # Disabled - use your preferred terminal
      };
      alacritty = {
        enable = false;
      };
      # Editor
      vim = {
        enable = false;
      };
      # Misc
      bat = {
        enable = true;
      };
      fish = {
        enable = true;
      };
      fzf = {
        enable = true;
      };
      btop = {
        enable = true;
      };
      # GTK/Qt
      gtk = {
        enable = true;
      };
      qt = {
        enable = true;
      };
    };
  };
}
