# Fix home directory permissions for Nix builds
# Nix colmena deployments need read access to home directories
{ config, lib, pkgs, ... }:

{
  systemd.services.fix-home-permissions = {
    description = "Fix Home Directory Permissions for Nix Builds";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe pkgs.bash + " -c 'chmod 755 ~j_kro'";
      User = "root";
    };
  };
}
