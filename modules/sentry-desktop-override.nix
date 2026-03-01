# Plasma Manager Override for Sentry
# Sentry uses Hyprland, not Plasma, so we disable plasma-manager here
{
  pkgs,
  lib,
  ...
}: {
  # Disable Plasma components
  programs.plasma = lib.mkForce false;

  # This module exists just to override plasma-manager from common-base.nix
  # Sentry imports this module after common-base.nix
}
