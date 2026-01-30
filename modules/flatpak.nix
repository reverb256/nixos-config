{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  # Enable Flatpak support using the standard NixOS module
  services.flatpak.enable = true;

  # Enable Flatpak PolicyKit rules to fix permissions
  services.flatpak.polkit.enable = true;
  services.flatpak.polkit.allowAppstreamOperations = true;
  services.flatpak.polkit.allowUserOperations = true;
}
