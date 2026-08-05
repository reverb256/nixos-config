# Base aggregate (host-wiring Q4 → C; dissolve Q3 → B)
#
# Every host imports THIS first. It provides:
#   - common-host defaults (plumbing by path, NOT keyed features)
#   - system/network/ssh/tailscale plumbing (by path)
#   - network-constants (by path — the cluster constants other features read
#     via config.networking.cluster)
#
# Only "would a host import this by name?" features self-register under
# flake.nixosModules.*; everything here is plumbing → plain path imports.
{ inputs, ... }: {
  flake.modules.nixos.base = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [
      # Plumbing by path (dissolve Q3 → B) — NOT self-registered keys.
      # base.nix lives at modules/base.nix, so paths are relative to modules/.
      ./network-constants.nix
      ./common-host-defaults.nix
      ./system/system-packages.nix
      ./system/users.nix
      ./system/networking.nix
      ./system/ssh.nix
      ./system/tailscale.nix
      # ...the rest of the shared-defaults plumbing...
    ];
  };
}
