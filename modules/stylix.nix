# Stylix - Declarative Theming for NixOS
# This module provides theme selection for Stylix theming
# Note: Stylix is enabled in common-base.nix via stylix.enable = true

{ pkgs, config, ... }:
{
  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
  };
}
