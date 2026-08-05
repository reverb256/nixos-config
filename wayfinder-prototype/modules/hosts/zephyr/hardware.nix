# Zephyr hardware aggregate (host-wiring Q4 → C, Q5 → A)
#
# Per-host hardware module: wraps the GENERATED hardware-configuration.nix
# (plain path import — never keyed, never edited) + GPU/VM hardware modules.
# Real repo: hosts/zephyr/hardware-configuration.nix is machine output from
# nixos-generate-config; here a minimal stand-in so the reference evaluates.
{ inputs, ... }: {
  flake.modules.nixos.zephyrHardware = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [
      # Generated file — plain path import (host-wiring Q5 → A)
      ./hardware-configuration.nix
      # Shared GPU/hardware features (self-registering in real repo)
      # config.flake.nixosModules.nvidia-common
      # config.flake.nixosModules.nvidia-wayland
      # ...hardware features zephyr needs...
    ];
  };
}
