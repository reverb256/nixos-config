# users — plumbing (dissolve Q3 → B) — MINIMAL STAND-IN
#
# Real repo: modules/system/users.nix (j_kro user + groups).
{ config, lib, pkgs, ... }: {
  users.users.j_kro = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
}
