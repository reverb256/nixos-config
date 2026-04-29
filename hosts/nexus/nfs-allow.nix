{ config, lib, ... }:
{
  # Allow NFS kernel modules — nix-mineral security hardening blacklists them
  # but our cluster needs NFS mounts from zephyr for config sharing
  boot.kernelModules = lib.mkAfter [ "nfs" "nfsv4" ];

  # Override nix-mineral's NFS blacklists WITHOUT wiping other modprobe config
  # WARNING: Do NOT use boot.extraModprobeConfig = lib.mkForce "" — it breaks boot!
  environment.etc."modprobe.d/nfs-allow.conf".text = ''
    install nfs /run/current-system/sw/bin/modprobe --ignore-install nfs
    install nfs_acl /run/current-system/sw/bin/modprobe --ignore-install nfs_acl
    install nfsd /run/current-system/sw/bin/modprobe --ignore-install nfsd
    install nfsv4 /run/current-system/sw/bin/modprobe --ignore-install nfsv4
  '';
}
