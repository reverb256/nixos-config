# tailscale — plumbing (dissolve Q3 → B) — MINIMAL STAND-IN
#
# Real repo: modules/system/tailscale.nix (tailscale mesh + CGNAT routes).
{ config, lib, pkgs, ... }: {
  services.tailscale.enable = lib.mkDefault false;
}
