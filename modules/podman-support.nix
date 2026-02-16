# Podman Support Module
# Enables Podman container runtime for Nanoclaw deployment
# Podman is preferred over Docker on NixOS (more native, better integration)
{ pkgs, lib, config, ... }:
with lib;
let cfg = config.virtualisation.podman or {};
in {
  options.virtualisation.podman = {
    enable = lib.mkEnableOption "Enable Podman container runtime";
    dockerCompat = lib.mkEnableOption "Enable Docker compatibility (provides docker alias)";
    defaultPolicy = lib.mkOption {
      type = lib.types.enum ["sigpolicy" "runroot" "leastprivilege"];
      default = "sigpolicy";
      description = "Default Podman security policy";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable Podman
    virtualisation.podman = {
      inherit (cfg);
      dockerCompat = cfg.dockerCompat or true;
    };

    # Add Docker compatibility alias
    environment.systemPackages = lib.mkIf cfg.dockerCompat [ pkgs.podman ];

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
