# Desktop Profile
# Composable profile for desktop hosts (zephyr, nexus, forge)
{
  lib,
  config,
  ...
}:
with lib; {
  imports = [
    ../../core/base.nix
    ../../core/users.nix
    ../../core/networking.nix
    ../../core/nix-config.nix

    ../../desktop/plasma.nix

    # Import shared modules from legacy modules/
    ../../modules/desktop.nix
    ../../modules/fish-starship.nix
    ../../modules/gaming.nix
    ../../modules/system-packages.nix
    ../../modules/ssh.nix
    ../../modules/systemd-slices.nix
    ../../modules/flatpak-polkit.nix
    ../../modules/minio-cache.nix
    ../../modules/vm-tuning.nix
    ../../modules/peripherals.nix
    ../../modules/keyboard-shortcuts.nix
    ../../modules/scopebuddy.nix
    ../../modules/security-hardware.nix
  ];
}
