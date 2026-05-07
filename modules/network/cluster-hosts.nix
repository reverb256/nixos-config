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
          zephyr = {ip = "10.1.1.110";};
          nexus = {ip = "10.1.1.120";};
          forge = {ip = "10.1.1.130";};
          sentry = {ip = "10.1.1.140";};
        }) [
          (lib.mapAttrsToList (name: host: "${host.ip} ${name}"))
          (lib.concatStringsSep "\n")
        ]
      )
    );
  };
}
