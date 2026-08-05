# system-packages — plumbing (dissolve Q3 → B) — MINIMAL STAND-IN
#
# Real repo: modules/system/system-packages.nix (baseline CLI packages).
{ config, lib, pkgs, ... }: {
  environment.systemPackages = with pkgs; [ curl jq git ];
}
