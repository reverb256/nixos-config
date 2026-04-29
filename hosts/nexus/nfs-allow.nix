{ pkgs, lib, ... }:
{
  # Allow NFS kernel modules — nix-mineral compatibility preset blocks them
  # but our cluster needs NFS mounts from zephyr
  boot.extraModprobeConfig = lib.mkForce "";
  
  # Override nix-mineral's modprobe.d NFS blocks by writing our own config
  # that loads after theirs
  environment.etc."modprobe.d/nix-mineral-nfs-override.conf".text = ''
    # Allow NFS — cluster requires it
    install nfs /run/current-system/sw/bin/modprobe -i nfs
    install nfs_acl /run/current-system/sw/bin/modprobe -i nfs_acl
    install nfsd /run/current-system/sw/bin/modprobe -i nfsd
    install nfsv4 /run/current-system/sw/bin/modprobe -i nfsv4
  '';
}
