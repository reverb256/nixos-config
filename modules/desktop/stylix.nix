{
  pkgs,
  lib,
  ...
}: {
  stylix = {
    enable = true;

    base16Scheme = lib.mkDefault "${pkgs.base16-schemes}/share/themes/nord.yaml";
    polarity = "dark";

    image = lib.mkDefault ./wallpapers/nord-bg.png;

    fonts = {
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };
      sansSerif = {
        package = pkgs.inter;
        name = "Inter";
      };
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
    };

    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 24;
    };

    opacity = {
      applications = 1.0;
      desktop = 1.0;
      popups = 0.95;
      terminal = 0.95;
    };

    autoEnable = true;
  };
}
