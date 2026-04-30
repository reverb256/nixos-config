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
    networking.extraHosts = lib.mkIf cfg.populateLocal (
      lib.mkOptionDefault (
        lib.pipe (config.networking.cluster.hosts or {
          zephyr = {ip = config.networking.cluster.hosts.zephyr.ip;};
          nexus = {ip = config.networking.cluster.hosts.nexus.ip;};
          forge = {ip = config.networking.cluster.hosts.forge.ip;};
          sentry = {ip = config.networking.cluster.hosts.sentry.ip;};
        }) [
          (lib.mapAttrsToList (name: host: "${host.ip} ${name}"))
          (lib.concatStringsSep "\n")
        ]
      )
    );
  };
}
