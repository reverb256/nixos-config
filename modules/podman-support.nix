# Podman Support Module
# Enables Podman container runtime for Nanoclaw deployment
# Podman is preferred over Docker on NixOS (more native, better integration)
{ pkgs, lib, config, ... }:
with lib;
let
  # Check if Podman is already configured
  isPodmanEnabled = config.virtualisation.podman.enable or false;
in {
  # Add Docker compatibility alias
  virtualisation.podman = {
    dockerCompat = lib.mkIf (!isPodmanEnabled) true;
    defaultPolicy = lib.mkIf (!isPodmanEnabled) (config.virtualisation.podman.defaultPolicy or "sigpolicy");
  };

  config = lib.mkIf (!isPodmanEnabled) {
    # Enable Podman
    virtualisation.podman.enable = true;

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
