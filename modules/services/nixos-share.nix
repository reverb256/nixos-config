# NixOS Configuration Share Module
# Allows remote hosts to mount /etc/nixos from zephyr for single-source-of-truth
#
# DESIGN NOTE: Client mount uses /run/nixos-shared instead of /etc/nixos
# This avoids bubblewrap conflicts with steam-run and other sandboxed applications
# that attempt to bind-mount the entire root filesystem.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.nixos-share;
in {
  options.services.nixos-share = {
    enable = lib.mkEnableOption "NixOS configuration sharing";

    server = {
      enable = lib.mkEnableOption "NFS server for sharing /etc/nixos";
      allowedHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["10.1.1.120" "10.1.1.130" "10.1.1.140"]; # nexus, forge, sentry (local network)
        description = "IP addresses allowed to mount the NFS share";
      };
    };

    client = {
      enable = lib.mkEnableOption "NFS client for mounting /etc/nixos from zephyr";
      serverHost = lib.mkOption {
        type = lib.types.str;
        default = "10.1.1.110"; # zephyr's local network IP
        description = "NFS server hostname or IP";
      };
      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = "/run/nixos-shared";
        description = "Where to mount the shared NixOS config (use /run to avoid bubblewrap conflicts)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # NFS Server configuration (for zephyr)
    # Server exports /etc/nixos (source of truth)
    services.nfs.server = lib.mkIf cfg.server.enable {
      enable = true;
      exports =
        lib.concatMapStringsSep "\n" (host: ''
          /etc/nixos ${host}(ro,no_subtree_check,no_root_squash,async,nohide,insecure)
        '')
        cfg.server.allowedHosts;
    };

    # Firewall rules to allow NFS traffic from allowed hosts
    networking.firewall = lib.mkIf cfg.server.enable {
      allowedTCPPorts = lib.mkOptionDefault [111 2049 20048];
      extraCommands =
        lib.concatMapStringsSep "\n" (host: ''
          iptables -I nixos-fw -p tcp -s ${host} --dport 111 -j ACCEPT
          iptables -I nixos-fw -p tcp -s ${host} --dport 2049 -j ACCEPT
          iptables -I nixos-fw -p tcp -s ${host} --dport 20048 -j ACCEPT
        '')
        cfg.server.allowedHosts;
    };

    # NFS Client configuration (for remote hosts)
    # Client mounts to /run/nixos-shared (not /etc/nixos) to avoid bubblewrap conflicts
    fileSystems = lib.mkIf cfg.client.enable {
      "${cfg.client.mountPoint}" = {
        device = "${cfg.client.serverHost}:/etc/nixos";
        fsType = "nfs";
        # Use nofail to prevent boot hang, bg for background mount
        # x-systemd.mount-timeout=30s gives up quickly if server not ready
        options = ["ro" "noatime" "hard" "intr" "timeo=600" "retrans=2" "_netdev" "nofail" "bg" "x-systemd.mount-timeout=30s"];
      };
    };

    # Create a symlink from /etc/nixos-shared to the actual mount point
    # This provides a convenient path that works regardless of mount point changes
    systemd.tmpfiles.rules = lib.mkIf cfg.client.enable [
      "L+ /etc/nixos-shared - - - - ${cfg.client.mountPoint}"
    ];

    # Set an environment variable for tools that need the shared config path
    environment.variables.NIXOS_SHARED_PATH = lib.mkIf cfg.client.enable cfg.client.mountPoint;
  };
}
