# NixOS Configuration Share Module
# Allows remote hosts to mount /etc/nixos from zephyr for single-source-of-truth
{
  config,
  lib,
  pkgs,
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
        default = ["100.86.158.18" "100.95.222.45" "100.81.171.24"]; # nexus, forge, sentry
        description = "IP addresses allowed to mount the NFS share";
      };
    };

    client = {
      enable = lib.mkEnableOption "NFS client for mounting /etc/nixos from zephyr";
      serverHost = lib.mkOption {
        type = lib.types.str;
        default = "100.95.129.98"; # zephyr's Tailscale IP
        description = "NFS server hostname or IP";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # NFS Server configuration (for zephyr)
    services.nfs.server = lib.mkIf cfg.server.enable {
      enable = true;
      exports = lib.concatMapStringsSep "\n" (host: ''
        /etc/nixos ${host}(ro,no_subtree_check,no_root_squash,async,nohide,insecure)
      '') cfg.server.allowedHosts;
    };

    # NFS Client configuration (for remote hosts)
    fileSystems = lib.mkIf cfg.client.enable {
      "/etc/nixos" = {
        device = "${cfg.client.serverHost}:/etc/nixos";
        fsType = "nfs";
        # Use nofail to prevent boot hang, bg for background mount
        # x-systemd.mount-timeout=30s gives up quickly if server not ready
        options = ["ro" "noatime" "soft" "timeo=5" "retrans=2" "_netdev" "nofail" "bg" "x-systemd.mount-timeout=30s"];
      };
    };
  };
}
