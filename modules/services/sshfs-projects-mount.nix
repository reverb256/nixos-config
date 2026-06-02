{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.sshfs-projects-mount;
in {
  options.services.sshfs-projects-mount = {
    enable = lib.mkEnableOption "SSHFS mount for /data/projects/own from zephyr";

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "SSH user on the remote host";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "zephyr";
      description = "Remote SSHFS host";
    };

    remotePath = lib.mkOption {
      type = lib.types.str;
      default = "/data/projects/own";
      description = "Remote directory to mount";
    };

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/data/projects/own";
      description = "Local mount point";
    };

    identityFile = lib.mkOption {
      type = lib.types.str;
      default = "/home/j_kro/.ssh/id_ed25519";
      description = "SSH identity file for authentication";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.sshfs];

    # FUSE config: allow_other required for SSHFS mounts owned by root
    environment.etc."fuse.conf".text = ''
      user_allow_other
    '';

    # Resilient SSHFS mount:
    # - nofail: don't block boot if zephyr is down
    # - _netdev: network filesystem, delay until network is up
    # - x-systemd.automount: mount on first access, skip at boot
    # - x-systemd.device-timeout=10s: fail fast if unreachable
    # - x-systemd.mount-timeout=30s: systemd-level timeout cap
    fileSystems."/data/projects/own" = {
      device = "${cfg.user}@${cfg.host}:${cfg.remotePath}";
      fsType = "fuse.sshfs";
      options = [
        "reconnect"
        "ServerAliveInterval=15"
        "ServerAliveCountMax=3"
        "allow_other"
        "default_permissions"
        "IdentityFile=${cfg.identityFile}"
        "nofail"
        "_netdev"
        "x-systemd.automount"
        "x-systemd.device-timeout=10s"
        "x-systemd.mount-timeout=30s"
      ];
    };

    # Create mount point directory so services don't crash when zephyr is down
    systemd.tmpfiles.rules = [
      "d /data/projects/own 0755 root root -"
    ];
  };
}
