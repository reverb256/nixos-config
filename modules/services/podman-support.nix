{
  pkgs,
  lib,
  ...
}:
with lib; {
  config = {
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    environment.systemPackages = [pkgs.podman];

    users.users.j_kro.extraGroups = ["podman"];
  };
}
