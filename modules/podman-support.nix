# Podman Support Module
# Enables Podman container runtime for Nanoclaw deployment
# Podman is preferred over Docker on NixOS (more native, better integration)
{ pkgs, lib, config, ... }:
with lib;
let cfg = config.virtualisation.podman or {};
in {
  # Add Docker compatibility alias
  virtualisation.podman = {
    dockerCompat = lib.mkIf (cfg.dockerCompat or true) true;
    defaultPolicy = lib.mkIf (cfg.defaultPolicy or "sigpolicy") cfg.defaultPolicy;
  };

  config = lib.mkIf cfg.enable {
    # Enable Podman
    virtualisation.podman = {
      inherit (cfg);
      enable = true;
      dockerCompat = cfg.dockerCompat or true;
      defaultPolicy = cfg.defaultPolicy or "sigpolicy";
    };

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
