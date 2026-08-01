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
    # Qt target only — the cluster runs niri, NOT Plasma, so KDE/Plasma
    # targets are intentionally not empowered here. NOTE: the HM-side
    # `stylix.targets.kde` option DOES exist in the pinned stylix
    # (modules/kde/hm.nix, defaults to ENABLED) — it is explicitly
    # disabled in the shared HM stylix targets
    # (modules/home-manager/shared-leaf-modules.nix) so the
    # stylix-kde-apply-plasma-theme activation stops firing on every
    # `home-manager switch` for non-Plasma sessions.
    # autoEnable=false keeps stylix from touching unlisted targets
    # (the NixOS-side kde target historically caused "option does not
    # exist" eval errors when autoEnable probed it).
    targets.qt.enable = true;
    # Avoid qtct→kvantum (default for non-GNOME/non-Plasma-only DEs).
    # Cluster runs niri; use gnome platform → adwaita-dark so Qt matches
    # GTK (adw-gtk3) without Kvantum plugins (removed for Plasma6/NVIDIA
    # crash risk; also fragile when theme files are missing).
    # mkForce: override stylix DE-detect (niri is neither pure GNOME nor pure
    # Plasma6, so the module would set qtct → kvantum).
    targets.qt.platform = lib.mkForce "qtct";

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

  # ── Register the monospace Nerd Font with fontconfig ──────────
  # Stylix sets `monospace.package = pkgs.nerd-fonts.jetbrains-mono` (the
  # *alias* name "JetBrainsMono Nerd Font"), but that alone does NOT put the
  # font files on fontconfig's search path. Without this, `fc-match
  # "JetBrainsMono Nerd Font"` resolves to DejaVu Sans, so terminals /
  # fastfetch / starship render Nerd glyphs as missing-character squares.
  # Adding the package to `fonts.packages` symlinks it into the font dir and
  # registers it with fontconfig system-wide.
  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

}