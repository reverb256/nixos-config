# User Accounts Module
{ config, lib, pkgs, ... }:
{
  users.users.j_kro = {
    isNormalUser = true;
    description = "Jeremy Kroeker";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" "render" "video" "libinput" ];
    packages = with pkgs; [
      kdePackages.kate
      gh  # GitHub CLI
      nodejs  # Node.js runtime
    ];
  };

  # Allow passwordless sudo for j_kro
  security.sudo = {
    enable = true;
    extraConfig = "j_kro ALL=(ALL) NOPASSWD: ALL";
  };
}
