# Zephyr hardware-configuration.nix — MINIMAL STAND-IN
#
# In the real repo this is MACHINE-GENERATED (nixos-generate-config) and lives
# at hosts/zephyr/hardware-configuration.nix. It is treated as data: imported
# by path, never keyed, never edited (host-wiring Q5 → A). This stand-in exists
# only so the throwaway reference flake evaluates; it is NOT a model for what
# the real generated file should look like.
{ config, lib, pkgs, ... }: {
  # Minimal real content: bootloader + filesystems declarations sufficient for
  # a nixosSystem eval. Real generated file has the full partition layout.
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/nixos-root";
    fsType = "btrfs";
  };
}
