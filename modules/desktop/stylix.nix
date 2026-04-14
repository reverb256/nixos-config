{ config, pkgs, lib, ... }:
{
  # Stylix — Declarative theming for NixOS
  # Per-host color scheme set in hosts/<name>/configuration.nix.
  # Shared settings: fonts, opacity, polarity, auto-enable.
  # Auto-detected targets: noctalia-shell, ghostty, fish, bat, fzf, tmux,
  #   helix, neovim, lazygit, starship, btop, chromium, obsidian, etc.

  stylix = {
    enable = true;

    # Default theme — overridden per-host in hosts/<name>/configuration.nix
    # Zephyr: nord | Nexus: catppuccin-mocha | Forge: gruvbox-dark-medium | Sentry: dracula
    base16Scheme = lib.mkDefault "${pkgs.base16-schemes}/share/themes/nord.yaml";
    polarity = "dark";

    # Default wallpaper — overridden per-host
    image = lib.mkDefault ./wallpapers/nord-bg.png;

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
