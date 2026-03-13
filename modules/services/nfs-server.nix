# NFS Server for cluster-wide file sharing
# Runs on Nexus (10.1.1.120) - the storage node
{
  config,
  lib,
  ...
}: let
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

    # Firewall for NFS - use extraCommands to directly add iptables rules
    # This is needed because lib.mkOptionDefault doesn't properly merge
    # when multiple modules set firewall.allowedTCPPorts
    networking.firewall.extraCommands = ''
      # NFS server ports - allow from entire cluster network
      iptables -I nixos-fw -s 10.1.1.0/24 -p tcp --dport 111 -j ACCEPT
      iptables -I nixos-fw -s 10.1.1.0/24 -p tcp --dport 2049 -j ACCEPT
      iptables -I nixos-fw -s 10.1.1.0/24 -p tcp --dport 20048 -j ACCEPT
      iptables -I nixos-fw -s 10.1.1.0/24 -p udp --dport 111 -j ACCEPT
      iptables -I nixos-fw -s 10.1.1.0/24 -p udp --dport 2049 -j ACCEPT
      iptables -I nixos-fw -s 10.1.1.0/24 -p udp --dport 20048 -j ACCEPT
    '';

    # Fixed rpc.mountd port for firewall (this may need adjustment)
    # Note: rpc.mountd port configuration is handled via --port in newer nfs-utils
  };
}
