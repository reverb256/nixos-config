# networking — plumbing (dissolve Q3 → B) — MINIMAL STAND-IN
#
# Real repo: modules/system/networking.nix (interfaces, DNS, tailscale mesh).
{ config, lib, pkgs, ... }: {
  networking.useDHCP = lib.mkDefault true;
}
