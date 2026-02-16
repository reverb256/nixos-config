# Podman Support Module
# Enables Podman container runtime for Nanoclaw deployment
# Podman is preferred over Docker on NixOS (more native, better integration)
{ pkgs, lib, config, ... }:
with lib;
let
  # Check if Podman is already configured
  isPodmanEnabled = config.virtualisation.podman.enable or false;
in {
  config = lib.mkIf (!isPodmanEnabled) {
    # Enable Podman if not already enabled
    virtualisation.podman.enable = true;

    # Add Docker compatibility alias (enables `docker` command as alias to `podman`)
    virtualisation.podman.dockerCompat = true;

    # Add Podman to system packages
    environment.systemPackages = [ pkgs.podman ];

    # Add j_kro to podman group for non-root container access
    users.users.j_kro.extraGroups = lib.mkAfter config.users.users.j_kro ["podman"];

    # Configure Podman storage (optional, defaults to /var/lib/containers)
    # Can be customized via:
    # environment.etc."containers/storage.conf".text = ''
    #   [storage]
    #   driver = "overlay"
    #   runroot = "/run/containers"
    #   graphroot = "/var/lib/containers/storage"
    # '';
  };
}
