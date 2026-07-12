{ pkgs, lib, config, ... }:
{
  stylix = {
    # Stylix is pinned to a newer commit than the 26.05 Nixpkgs we track.
    # The upstream version-mismatch check is a warning, not an error; we
    # intentionally track a newer Stylix, so silence the noise.
    enableReleaseChecks = false;
    enable = lib.mkDefault true;
    base16Scheme = lib.mkDefault "${pkgs.base16-schemes}/share/themes/nord.yaml";
    polarity = "dark";

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

      sizes = {
        terminal = 10;
      };
    };

    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 24;
    };

    icons = {
      enable = true;
      package = pkgs.papirus-icon-theme;
      dark = "Papirus-Dark";
      light = "Papirus-Light";
    };

    opacity = {
      applications = 1.0;
      desktop = 1.0;
      popups = 0.95;
      terminal = 0.95;
    };

    autoEnable = true;

    homeManagerIntegration = {
      followSystem = true;
      autoImport = true;
    };
  };

  # aagl (Gtk app wrapper) tracks its own 26.11 release branch while we stay on
  # Nixpkgs 26.05. The branch-mismatch check is a warning; we intentionally run
  # aagl ahead of Nixpkgs, so disable the check rather than chase a matching
  # aagl release that may not be published for 26.05.
  aagl = {
    enableNixpkgsReleaseBranchCheck = false;
  };
}