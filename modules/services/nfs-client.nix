# NFS Client for mounting shared storage from Nexus
{config, lib, pkgs, ...}: let
  cfg = config.services.nfs-client;
  nfsServer = "10.1.1.120";  # Nexus
in {
  options.services.nfs-client = {
    enable = lib.mkEnableOption "NFS client for cluster storage";

    mountShared = lib.mkEnableOption "mount /data/shared from NFS";

    mountHome = lib.mkEnableOption "mount /data/home from NFS";

    mountMedia = lib.mkEnableOption "mount /data/media (read-only) from NFS";
  };

  config = lib.mkIf cfg.enable {
    # NFS client packages
    environment.systemPackages = with pkgs; [nfs-utils];

    # NFS client settings
    services.rpcbind.enable = true;

    # Create mount points
    system.activationScripts.nfs-mounts = lib.stringAfter ["var"] ''
      mkdir -p /data/shared /data/home /data/media
    '';

    # Filesystem mounts
    fileSystems = lib.mkMerge [
      (lib.mkIf cfg.mountShared {
        "/data/shared" = {
          device = "${nfsServer}:/data/shared";
          fsType = "nfs";
          options = [
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.device-timeout=5s"
            "_netdev"
            "noatime"
            "rw"
          ];
        };
      })
      (lib.mkIf cfg.mountHome {
        "/data/home" = {
          device = "${nfsServer}:/data/home";
          fsType = "nfs";
          options = [
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.device-timeout=5s"
            "_netdev"
            "noatime"
            "rw"
          ];
        };
      })
      (lib.mkIf cfg.mountMedia {
        "/data/media" = {
          device = "${nfsServer}:/data/media";
          fsType = "nfs";
          options = [
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.device-timeout=5s"
            "_netdev"
            "noatime"
            "ro"
          ];
        };
      })
    ];

    # Network dependency - don't try to mount until network is ready
    systemd.targets."remote-fs-pre".wants = ["network-online.target"];
  };
}
