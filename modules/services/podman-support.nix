{
  pkgs,
  lib,
  ...
}:
with lib; {
  config = {
    virtualisation.podman = {
      enable = lib.mkDefault true;
      dockerCompat = true;
    };

    environment.systemPackages = [pkgs.podman];

    users.users.j_kro.extraGroups = ["podman"];
  };
}
