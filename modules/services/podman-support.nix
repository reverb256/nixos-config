# Podman Support Module
# Enables Podman container runtime for containerized workloads
# Podman is preferred over Docker on NixOS (more native, better integration)
#
# NOTE: This module is optional - only import on hosts that need Podman.
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.podman-support;
in {
  options.services.podman-support = {
    enable = lib.mkEnableOption "Podman container runtime support";

    dockerCompat = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Docker compatibility (docker command as alias to podman)";
    };

    addUserToGroup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add user j_kro to podman group for non-root container access";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable Podman runtime
    virtualisation.podman = {
      enable = true;
      # Add Docker compatibility alias if enabled
      dockerCompat = cfg.dockerCompat;
    };

    # Add Podman to system packages
    environment.systemPackages = [pkgs.podman];

    # Add j_kro to podman group for non-root container access
    users.users.j_kro = lib.mkIf cfg.addUserToGroup {
      extraGroups = ["podman"];
    };
  };
}
