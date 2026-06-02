{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
  cfg = config.services.nixos-share;
in {
  options.services.nixos-share = {
    enable = lib.mkEnableOption "NixOS configuration sharing";

    server = {
      enable = lib.mkEnableOption "NFS server for sharing";
      allowedHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          cluster.hosts.nexus.ip # nexus
          cluster.hosts.forge.ip # forge
          cluster.hosts.sentry.ip # sentry
        ];
        description = "IP addresses allowed to mount the NFS share";
      };
      exports = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            path = lib.mkOption {type = lib.types.path;};
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
          };
        });
        default = [
          {
            path = "/etc/nixos";
            description = "NixOS configuration";
          }
        ];
        description = "List of directories to export via NFS";
      };
    };

    client = {
      enable = lib.mkEnableOption "NFS client for mounting /etc/nixos from zephyr";
      serverHost = lib.mkOption {
        type = lib.types.str;
        default = cluster.hosts.zephyr.ip; # zephyr
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
    services.nfs.server = lib.mkIf cfg.server.enable {
      enable = true;
      exports = lib.mkDefault (
        let
          combinations =
            lib.concatMap (
              export:
                map (host: {
                  path = export.path;
                  host = host;
                })
                cfg.server.allowedHosts
            )
            cfg.server.exports;
        in
          lib.concatMapStringsSep "\n" (combo: ''
            ${combo.path} ${combo.host}(ro,no_subtree_check,async,nohide,insecure)
          '')
          combinations
      );
    };

    networking.firewall = lib.mkIf cfg.server.enable {
      allowedTCPPorts = lib.mkOptionDefault [
        111
        2049
        20048
      ];
      extraInputRules =
        lib.concatMapStringsSep "\n" (host: ''
          ip saddr ${host} tcp dport { 111, 2049, 20048 } accept
        '')
        cfg.server.allowedHosts;
    };

    fileSystems = lib.mkIf cfg.client.enable {
      "${cfg.client.mountPoint}" = {
        device = "${cfg.client.serverHost}:/etc/nixos";
        fsType = "nfs";
        options = [
          "ro"
          "noatime"
          "soft"
          "timeo=50"
          "retrans=2"
          "_netdev"
          "nofail"
          "bg"
          "x-systemd.mount-timeout=10s"
          "x-systemd.umount-timeout=10s"
        ];
      };
    };

    systemd.tmpfiles.rules = lib.mkIf cfg.client.enable [
      "L+ /etc/nixos-shared - - - - ${cfg.client.mountPoint}"
    ];

    environment.variables.NIXOS_SHARED_PATH = lib.mkIf cfg.client.enable cfg.client.mountPoint;
  };
}
