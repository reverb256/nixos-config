# common-host-defaults — plumbing (dissolve Q3 → B) — MINIMAL STAND-IN
#
# Real repo: modules/common-host-defaults.nix (baseline settings every host
# gets). This stand-in exists only so the reference flake evaluates.
{ config, lib, pkgs, ... }: {
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "24.11";
}
