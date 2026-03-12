# NFS Server for cluster-wide file sharing
# Runs on Nexus (10.1.1.120) - the storage node
{config, lib, pkgs, ...}: let
  cfg = config.services.nfs.server;
in {
  config = lib.mkIf cfg.enable {
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
    '';

    # NFSv4 idmapd configuration
    services.nfs.settings = {
      idmapd = {
        Domain = "cluster.local";
        Local-Realms = "cluster.local";
      };
    };

    # Firewall for NFS
    networking.firewall = {
      allowedTCPPorts = lib.mkOptionDefault [2049 111 20048];
      allowedUDPPorts = lib.mkOptionDefault [2049 111 20048];
    };

    # Fixed rpc.mountd port for firewall (this may need adjustment)
    # Note: rpc.mountd port configuration is handled via --port in newer nfs-utils
  };
}
