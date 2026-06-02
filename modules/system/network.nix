{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.cluster;
in {
  # Auto-generate /etc/hosts from cluster topology (DNS fallback)
  networking.extraHosts = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: host: "${host.ip} ${name}.cluster.local ${name}"
    )
    cfg.hosts
  );
}
