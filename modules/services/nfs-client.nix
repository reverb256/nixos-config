# NFS Client for mounting shared storage from Nexus
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
    # NFS client packages
    environment.systemPackages = with pkgs; [nfs-utils];

    # NFS client settings
    services.rpcbind.enable = true;

    # Create mount points for local directories only
    # Note: Automount paths (/data/shared, /data/home, /data/media) don't need mkdir
    # They will be created automatically by systemd when first accessed
    system.activationScripts.nfs-mounts = lib.stringAfter ["var"] ''
      # Skip creating directories for automount paths - they don't exist until accessed
      # The NFS mounts will create these directories automatically when needed
    '';

    # Filesystem mounts
    fileSystems = lib.mkMerge [
      (lib.mkIf cfg.mountShared {
        "/data/shared" = {
          device = "${cfg.serverIp}:/data/shared";
          fsType = "nfs4";
          # GRACEFUL FAILURE OPTIONS:
          # - soft: Return errors after timeout instead of hanging indefinitely
          # - timeo=50: 5 second timeout (in deciseconds)
          # - retrans=2: Give up after 2 retries (total ~10 seconds)
          # - x-systemd.automount: Mount on first access, not at boot
          # - x-systemd.device-timeout=5s: Give up on device after 5s
          # - nofail: Don't fail boot if NFS server is down
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

    # Network dependency - don't try to mount until network is ready
    systemd.targets."remote-fs-pre".wants = ["network-online.target"];
  };
}
