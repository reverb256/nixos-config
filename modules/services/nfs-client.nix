{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nfs-client;
in {
  options.services.nfs-client = {
    enable = lib.mkEnableOption "NFS client for cluster storage";

    mountShared = lib.mkEnableOption "mount /data/shared from NFS";

    mountHome = lib.mkEnableOption "mount /data/home from NFS";

    mountMedia = lib.mkEnableOption "mount /data/media (read-only) from NFS";

    serverIp = lib.mkOption {
      type = lib.types.str;
      default = config.networking.cluster.hosts.nexus.ip;
      description = "NFS server IP address";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [nfs-utils];

    services.rpcbind.enable = true;


    fileSystems = lib.mkMerge [
      (lib.mkIf cfg.mountShared {
        "/data/shared" = {
          device = "${cfg.serverIp}:/data/shared";
          fsType = "nfs4";
          options = [
            "soft"
            "timeo=50"
            "retrans=2"
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.device-timeout=5s"
            "x-systemd.mount-timeout=10s"
            "_netdev"
            "noatime"
            "rw"
          ];
        };
      })
      (lib.mkIf cfg.mountHome {
        "/data/home" = {
          device = "${cfg.serverIp}:/data/home";
          fsType = "nfs4";
          options = [
            "soft"
            "timeo=50"
            "retrans=2"
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.device-timeout=5s"
            "x-systemd.mount-timeout=10s"
            "_netdev"
            "noatime"
            "rw"
          ];
        };
      })
      (lib.mkIf cfg.mountMedia {
        "/data/media" = {
          device = "${cfg.serverIp}:/data/media";
          fsType = "nfs4";
          options = [
            "soft"
            "timeo=50"
            "retrans=2"
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.device-timeout=5s"
            "x-systemd.mount-timeout=10s"
            "_netdev"
            "noatime"
            "ro"
          ];
        };
      })
    ];

    systemd.targets."remote-fs-pre".wants = ["network-online.target"];
  };
}
