{
  config,
  lib,
  ...
}:
let
  cfg = config.services.nfs-cluster-mounts;
in
{
  options.services.nfs-cluster-mounts = {
    enable = lib.mkEnableOption "Resilient NFS cluster mounts with failover";

    # Hermes agent state (primary: zephyr, secondary: sentry)
    mountHermes = lib.mkEnableOption "mount ~/.hermes via NFS";

    # Pi agent state (primary: zephyr, secondary: sentry)
    mountPi = lib.mkEnableOption "mount ~/.pi/agent via NFS";

    primaryHost = lib.mkOption {
      type = lib.types.str;
      default = "zephyr";
      description = "Primary NFS server hostname (canonical: zephyr)";
    };

    secondaryHost = lib.mkOption {
      type = lib.types.str;
      default = "sentry";
      description = "Secondary/failover NFS server hostname";
    };
  };

  config = lib.mkIf cfg.enable {
    # Resilient NFS mount options:
    # - nofail: don't block boot if server is down
    # - soft: return EIO instead of infinite hang (acceptable for agent state)
    # - timeo=30, retrans=2: fail fast (60s max instead of 120s default)
    # - x-systemd.automount: mount on first access, skip at boot
    # - x-systemd.idle-timeout=10min: unmount when idle
    # - x-systemd.mount-timeout=15s: systemd-level timeout cap

    fileSystems = lib.mkMerge [
      (lib.mkIf cfg.mountHermes {
        "/home/j_kro/.hermes" = {
          device = "${cfg.primaryHost}:/data/hermes";
          fsType = "nfs4";
          options = [
            "noatime"
            "nodiratime"
            "_netdev"
            "nofail"
            "soft"
            "timeo=30"
            "retrans=2"
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.mount-timeout=15s"
          ];
        };
      })

      (lib.mkIf cfg.mountPi {
        "/home/j_kro/.pi/agent" = {
          device = "${cfg.primaryHost}:/data/pi";
          fsType = "nfs4";
          options = [
            "noatime"
            "nodiratime"
            "_netdev"
            "nofail"
            "soft"
            "timeo=30"
            "retrans=2"
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.mount-timeout=15s"
          ];
        };
      })
    ];

    # Create local fallback directories so services don't crash
    # when NFS is unavailable. These are populated by the mount when available.
    systemd.tmpfiles.rules = lib.mkMerge [
      (lib.mkIf cfg.mountHermes [
        "d /home/j_kro/.hermes 0700 j_kro users -"
      ])
      (lib.mkIf cfg.mountPi [
        "d /home/j_kro/.pi 0755 j_kro users -"
        "d /home/j_kro/.pi/agent 0755 j_kro users -"
      ])
    ];
  };
}
