# ssh — plumbing (dissolve Q3 → B) — MINIMAL STAND-IN
#
# Real repo: modules/system/ssh.nix (sshd, keys, auth).
{ config, lib, pkgs, ... }: {
  services.openssh.enable = lib.mkDefault true;
}
