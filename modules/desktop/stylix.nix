{ pkgs, lib, config, ... }:
{
  stylix = {
    # Stylix is pinned to a newer commit than the 26.05 Nixpkgs we track.
    # The upstream version-mismatch check is a warning, not an error; we
    # intentionally track a newer Stylix, so silence the noise.
    enableReleaseChecks = false;
    enable = lib.mkDefault true;
    # 2026-07-15: renamed the theme from "Nord" to "Osaka Jade" (real Omarchy
    # palette). Uses the repo-local base16 scheme below as the single source
    # of truth so the name is correct end-to-end.
    base16Scheme = lib.mkDefault ../modules/desktop/themes/osaka-jade.yaml;
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

    # ── KDE / Qt targets ───────────────────────────────────────
    # 2026-07-15: Dolphin (a Qt/KDE app) was unreadable because its
    # folder-view background is read from [Colors:View] in kdeglobals,
    # and the stale ~/.config/kdeglobals (April, Breeze-Dark) shadowed
    # stylix's generated copy. Enable both kde + qt targets so stylix
    # owns Dolphin's view colors AND Qt app theming end-to-end.
    # IMPORTANT: do NOT set targets.qt.platform = "qtct" — forcing qt5ct
    # is documented (stylix#971) to freeze the session.
    targets.qt.enable = true;

    autoEnable = true;

    homeManagerIntegration = {
      followSystem = true;
      autoImport = true;
    };
  };

}