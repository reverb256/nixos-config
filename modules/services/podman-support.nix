# Podman Support Module
# Enables Podman container runtime for Nanoclaw deployment
# Podman is preferred over Docker on NixOS (more native, better integration)
#
# NOTE: Import this module only on hosts where Nanoclaw will actually be deployed.
#
{
  pkgs,
  lib,
  ...
}:
with lib; {
  config = {
    # Enable Podman runtime
    virtualisation.podman = {
      enable = true;
      # Add Docker compatibility alias (enables `docker` command as alias to `podman`)
      dockerCompat = true;
    };

    # Add Podman to system packages
    environment.systemPackages = [pkgs.podman];

    # Add j_kro to podman group for non-root container access
    users.users.j_kro.extraGroups = ["podman"];
  };
}
