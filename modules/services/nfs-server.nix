{
  config,
  lib,
  ...
}:
let
  cfg = config.services.nfs.server;
in
{
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /mnt/garage 0755 root root - -"
      "d /mnt/garage/hermes 0775 root wheel - -"
    ];

    services.nfs.server.exports = ''
      /data/shared 10.1.1.0/24(rw,sync,no_subtree_check,crossmnt,no_root_squash,fsid=100)

      /data/home 10.1.1.0/24(rw,sync,no_subtree_check,crossmnt,no_root_squash,fsid=101)

      /data/media 10.1.1.0/24(ro,sync,no_subtree_check,crossmnt,fsid=102)

      /data/backups 10.1.1.0/24(ro,sync,no_subtree_check,crossmnt,fsid=103)

      /mnt/garage/hermes 10.1.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=104)

      /data/hermes 10.1.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=105)

      /data/pi 10.1.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=106)

      /data/qdrant 10.1.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=107)
    '';

    services.nfs.settings = {
      idmapd = {
        Domain = "cluster.local";
        Local-Realms = "cluster.local";
      };
    };

    networking.firewall.extraInputRules = ''
      ip saddr 10.1.1.0/24 tcp dport { 111, 2049, 20048 } accept
      ip saddr 10.1.1.0/24 udp dport { 111, 2049, 20048 } accept
    '';
  };
}
