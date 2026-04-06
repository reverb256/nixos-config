# NFS Server for cluster-wide file sharing
# Runs on Nexus (10.1.1.120) - the storage node
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
    # Create Hermes storage directory
    systemd.tmpfiles.rules = [
      "d /mnt/garage 0755 root root - -"
      "d /mnt/garage/hermes 0775 root wheel - -"
    ];

    # Export definitions for NFS server
    services.nfs.server.exports = ''
      # Shared data - read/write for all cluster nodes
      # SECURITY: no_root_squash allows root on client to have root access on server.
      # This is acceptable within the trusted cluster network (10.1.1.0/24) where
      # all nodes are under our control. Do not expose these exports to untrusted networks.
      /data/shared 10.1.1.0/24(rw,sync,no_subtree_check,crossmnt,no_root_squash,fsid=100)

      # User home directories - read/write for owner
      /data/home 10.1.1.0/24(rw,sync,no_subtree_check,crossmnt,no_root_squash,fsid=101)

      # Media library - read-only for most, write for admin
      /data/media 10.1.1.0/24(ro,sync,no_subtree_check,crossmnt,fsid=102)

      # Backups - read-only for clients (written locally)
      /data/backups 10.1.1.0/24(ro,sync,no_subtree_check,crossmnt,fsid=103)

      # Hermes Agent shared storage - skills, memory, and knowledge base
      /mnt/garage/hermes 10.1.1.0/24(rw,sync,no_subtree_check,no_root_squash,fsid=104)
    '';

    # NFSv4 idmapd configuration
    services.nfs.settings = {
      idmapd = {
        Domain = "cluster.local";
        Local-Realms = "cluster.local";
      };
    };

    # Firewall for NFS - allow from cluster network (nftables syntax)
    # Note: cluster-firewall.nix also covers these ports from cluster LAN
    networking.firewall.extraInputRules = ''
      ip saddr 10.1.1.0/24 tcp dport { 111, 2049, 20048 } accept
      ip saddr 10.1.1.0/24 udp dport { 111, 2049, 20048 } accept
    '';
  };
}
