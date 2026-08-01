# Hermes desktop entry for the Noctalia launcher
#
# hermes is installed via `nix profile install` (issue #334) — the hermes-desktop
# Tauri GUI binary lands in ~/.nix-profile/bin but ships NO .desktop file, so it
# never surfaces in the launcher. This module declares a proper .desktop entry
# (xdg.desktopEntries) with the OFFICIAL hermes icon, sourced from the profile
# store path via the stable ~/.nix-profile symlink (hash-independent).
#
# App discovery is filesystem-only (freedesktop Desktop Entry spec) — no
# portal/socket/D-Bus. The .desktop goes to ~/.local/share/applications (HM-
# managed) which the launcher scans; the Icon= absolute path resolves at launch.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Official hermes logo (1254x1254 RGBA PNG) shipped inside hermes-desktop.
  # Referenced through the stable ~/.nix-profile symlink so it survives store
  # hash changes across `nix profile upgrade`.
  hermesIcon =
    "${config.home.homeDirectory}/.nix-profile/share/hermes-desktop/dist/hermes.png";
in {
  # Enable xdg so desktopEntries/mimeApps are managed (idempotent; mimeApps
  # already relies on this elsewhere).
  xdg.enable = true;

  xdg.desktopEntries.hermes-desktop = {
    name = "Hermes Agent";
    exec = "hermes-desktop";
    icon = hermesIcon;
    comment = "Hermes — personal AI agent (desktop)";
    categories = [ "Development" "Utility" ];
    terminal = false;
    startupNotify = false;
  };
}
