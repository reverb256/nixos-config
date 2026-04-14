{ config, pkgs, lib, ... }:
{
  # Stylix — Declarative theming for NixOS
  # Applies unified Nord color scheme, fonts, and wallpaper across apps.
  # Auto-detected targets: noctalia-shell, ghostty, fish, bat, fzf, tmux,
  #   helix, neovim, lazygit, starship, btop, chromium, obsidian, etc.

  stylix = {
    enable = true;

    # Nord color scheme
    base16Scheme = "${pkgs.base16-schemes}/share/themes/nord.yaml";
    polarity = "dark";

    # Wallpaper — used by noctalia-shell, login screens, etc.
    image = ./wallpapers/nord-bg.png;

    # Fonts
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

    # Opacity
    opacity = {
      applications = 1.0;
      desktop = 1.0;
      popups = 0.95;
      terminal = 0.95;
    };

    # Auto-enable all detected targets
    autoEnable = true;
  };
}
