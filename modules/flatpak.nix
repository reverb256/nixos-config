{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  # Enable Flatpak support using the standard NixOS module
  services.flatpak.enable = true;
}
