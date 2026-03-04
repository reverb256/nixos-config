# Cluster Hosts Module
# Automatically populates /etc/hosts from networking.cluster.hosts configuration
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    attrValues
    mapAttrs'
    ;

  cfg = config.networking.cluster-hosts;
in
{
  options.networking.cluster-hosts = {
    enable = mkEnableOption "populate /etc/hosts from cluster configuration";

    populateLocal = mkEnableOption "add all cluster hosts to /etc/hosts (for name resolution)";
  };

  config = mkIf cfg.enable {
    # Build extraHosts from cluster hosts configuration
    networking.extraHosts = lib.mkIf cfg.populateLocal (
      lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: host: "${host.ip} ${name}"
        ) config.networking.cluster.hosts
      )
    );
  };
}
