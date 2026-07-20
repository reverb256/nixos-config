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
    base16Scheme = lib.mkDefault ./themes/osaka-jade.yaml;
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
    # Qt target only — the `kde` target was removed in newer stylix
    # and autoEnable tries to enable it when Plasma is running,
    # causing "option does not exist" eval errors. Explicit per-target
    # only covers what we actually run (Qt apps, not KDE/Plasma).
    targets.qt.enable = true;

    autoEnable = false;

    # ── NEW-APP THEMING RULE (read before adding a themed program) ──
    # autoEnable=false means stylix only themes targets that are EXPLICITLY
    # enabled. Terminal-app targets (starship, alacritty, kitty, fish, btop,
    # lazygit, gtk, qt, zen-browser) are HOME-MANAGER targets — empower them
    # in the HM `stylix` block (modules/system/home-manager.nix), NOT here at
    # the NixOS level (config.stylix.targets.* only carries system targets like
    # lightdm/limine and will throw "option does not exist"). System targets
    # (lightdm, limine, grub, etc.) ARE enabled here. So: when you add a new
    # themed app, add `stylix.targets.<x>.enable = true` in the correct
    # namespace or it will silently stay unthemed (no error, just wrong colors).

    homeManagerIntegration = {
      followSystem = true;
      autoImport = true;
    };
  };

}