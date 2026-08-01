# Canonical Home Manager leaf-module list — SINGLE SOURCE OF TRUTH.
#
# Both HM entrypoints consume this:
#   1. modules/system/home-manager.nix  (NixOS-module path, layer 2 activation today)
#   2. modules/home-manager/standalone.nix (flake homeConfigurations, portability artifact)
#
# Purpose: eliminate the divergence that caused recurring config drift
# (e.g. the starship "noctalia" WARN). Every user-env module lives here ONCE.
#
# RULE: nothing in this list may read NixOS-only options (config.services.*,
# config.programs.<nixos>, config.wayland.*). NixOS-coupled extras (niri-config,
# hermes symlink, noctalia spawn arg) are added by the NixOS-module path ONLY,
# in modules/system/home-manager.nix. firefox-pwa-apps is included but guards its
# NixOS-option read internally so it is safe on both paths.
#
# This is a function so each caller can append per-host / per-path extras.
{ lib, pkgs, ... }:
{
  # ── Shared leaf modules (HM-native, no NixOS-option dependency) ──
  leafModules = [
    ../../modules/home-manager/fish.nix
    ../../modules/home-manager/starship.nix
    ../../modules/home-manager/zen-browser.nix
    ../../modules/home-manager/nixcord-config.nix
    ../../modules/home-manager/caprine.nix
    ../../modules/home-manager/opencode.nix
    ../../modules/home-manager/firefox-pwa-apps.nix
    ../../modules/home-manager/alacritty.nix
    ../../modules/home-manager/hermes-skin.nix
    # Declarative hermes-gateway user unit (execs via %h/.nix-profile, self-healing)
    ../../modules/home-manager/hermes-gateway.nix
    ../../modules/home-manager/icon-theme.nix
    ../../modules/home-manager/dolphin.nix
    ../../modules/home-manager/desktop-utilities.nix
    ../../modules/home-manager/copyq.nix
    ../../modules/home-manager/git.nix
    ../../modules/home-manager/tmux.nix
    ../../modules/home-manager/lazygit.nix
    ../../modules/home-manager/mime-apps.nix
    ../../modules/home-manager/tui-apps.nix
    ../../modules/home-manager/editorconfig.nix
    ../../modules/home-manager/btop.nix
    # Freebuff Desktop launcher (.desktop only — binary is Layer 3, nix profile)
    ../../modules/home-manager/freebuff-desktop.nix
    # Stylix theming for noctalia desktop + purge frozen noctalia orphans
    ../../modules/home-manager/noctalia-stylix.nix
    # Reclaim stylix-bridged targets (qt/gtk/kitty) — HM-native
    ../../modules/home-manager/stylix-bridges.nix
    # Self-healing drift guard (un-freeze plain-file dotfiles before linkGen)
    ../../modules/home-manager/heal-stale-backups.nix
    # Hermes Desktop launcher entry (binary is Layer 3, nix profile — issue #334/#337)
    ../../modules/home-manager/hermes-desktop-entry.nix
    # Symlink nix-profile/system .desktop files into ~/.local/share/applications
    # so Noctalia + file pickers surface Layer-3 GUI apps (issue #335). Both HM
    # paths need this — was dropped from standalone.nix by the #338 refactor.
    ../../modules/home-manager/mime-fix.nix
  ];

  # ── Stylix target empowerment — MUST be shared so standalone HM is themed ──
  # (Previously only in the NixOS-module path, which left standalone unthemed.)
  stylixTargets = {
    targets.zen-browser.profileNames = [ "default" ];
    targets.starship.enable = true;
    targets.alacritty.enable = true;
    targets.kitty.enable = true;
    targets.fish.enable = true;
    targets.btop.enable = true;
    targets.lazygit.enable = true;
    targets.qt.enable = true;
    targets.qt.platform = lib.mkForce "qtct";
    # Cluster runs niri ONLY (no Plasma on any host). Stylix's kde target
    # defaults to ENABLED (mkEnableTarget "KDE" true), which runs the
    # stylix-kde-apply-plasma-theme activation on every `home-manager switch`
    # and spews noise on non-Plasma sessions:
    #   QApplication: invalid style override 'adwaita-dark'...
    #   "applications.menu" not found in QList(...)
    # Disable it here (shared, so both NixOS-module and standalone HM paths
    # behave identically). Re-enable if a host ever runs Plasma.
    targets.kde.enable = false;
    targets.gtk.enable = true;
    targets.bat.enable = true;
    targets.fzf.enable = true;
    targets.tmux.enable = true;
    targets.opencode.enable = true;
    targets.vesktop.enable = true;
  };
}
