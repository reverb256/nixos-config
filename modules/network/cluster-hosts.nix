# Cluster Hosts Module
# Automatically populates /etc/hosts from networking.cluster.hosts configuration
{
  config,
  lib,
  ...
}: let
  inherit
    (lib)
    mkEnableOption
    mkIf
    ;

  cfg = config.networking.cluster-hosts;
in {
  options.networking.cluster-hosts = {
    enable = mkEnableOption "populate /etc/hosts from cluster configuration";

    populateLocal = mkEnableOption "add all cluster hosts to /etc/hosts (for name resolution)";
  };

  config = mkIf cfg.enable {
    # Build extraHosts from cluster hosts configuration
    # Uses lib.pipe for clear functional transformation pipeline
    networking.extraHosts = lib.mkIf cfg.populateLocal (
      lib.pipe config.networking.cluster.hosts [
        # Transform: {name = {ip = ...}} -> ["ip name"]
        (lib.mapAttrsToList (name: host: "${host.ip} ${name}"))
        # Join: ["10.0.0.1 zephyr", "10.0.0.2 nexus"] -> "10.0.0.1 zephyr\n10.0.0.2 nexus"
        (lib.concatStringsSep "\n")
      ]
    );
  };
}
