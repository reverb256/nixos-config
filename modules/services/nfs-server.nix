{
  config,
  lib,
  ...
}: let
  cfg = config.services.nfs-data-server;

  baseExports = ''
    /data/shared 10.1.1.0/24(rw,sync,no_subtree_check,crossmnt,root_squash,anonuid=1000,anongid=100,fsid=100)

    /data/home 10.1.1.0/24(rw,sync,no_subtree_check,crossmnt,root_squash,anonuid=1000,anongid=100,fsid=101)

    /data/media 10.1.1.0/24(ro,sync,no_subtree_check,crossmnt,fsid=102)

    /data/backups 10.1.1.0/24(ro,sync,no_subtree_check,crossmnt,fsid=103)

    /mnt/garage/hermes 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=104)

    /data/models 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=108)

    /data/qdrant 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=107)

    /etc/nixos 10.1.1.0/24(ro,sync,no_subtree_check,fsid=109)

    /data/models 10.1.1.0/24(ro,sync,no_subtree_check,fsid=108)
  '';
in {
  options.services.nfs-data-server = {
    enable = lib.mkEnableOption "NFS data server (exports /data/* to cluster)";

    exports = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional NFS export entries for /data/* paths";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nfs.server.enable = true;

    systemd.tmpfiles.rules = [
      "d /mnt/garage 0755 root root - -"
      "d /mnt/garage/hermes 0775 root wheel - -"
      "d /data/models 1777 root root - -"
    ];

    # Base data exports -- only applied when nfs-data-server is enabled
    # Uses mkDefault so hosts can mkForce override with selective exports
    services.nfs.server.exports = lib.mkDefault (baseExports + cfg.exports);

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
