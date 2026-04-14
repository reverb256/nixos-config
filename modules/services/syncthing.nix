{
  config,
  lib,
  ...
}: let
  cfg = config.services.syncthing-cluster;
in {
  options.services.syncthing-cluster = {
    enable = lib.mkEnableOption "Syncthing P2P file sync for cluster";

    deviceId = lib.mkOption {
      type = lib.types.str;
      default = "PLACEHOLDER-DEVICE-ID";
      description = "This node's Syncthing device ID";
    };
  };

  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = "root";
      dataDir = "/var/lib/syncthing";
      configDir = "/var/lib/syncthing/.config/syncthing";

      openDefaultPorts = true;

      settings = {
        devices = {
          "zephyr" = {id = "ZEPYR-PLACEHOLDER";};
          "nexus" = {id = "NEXUS-PLACEHOLDER";};
          "forge" = {id = "FORGE-PLACEHOLDER";};
          "sentry" = {id = "SENTRY-PLACEHOLDER";};
        };

        folders = {
          "nixos-configs" = {
            path = "/etc/nixos";
            devices = ["zephyr" "nexus" "forge" "sentry"];
            ignorePerms = false;
            versioning = {
              type = "simple";
              params = {keep = "10";};
            };
          };
        };

        gui = {
          address = "127.0.0.1:8384";
          user = "j_kro";
        };

        options = {
          keepTemporariesHrs = 24;
          connectionsServiceEnabled = true;
        };
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22000 8384];
    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [21027 22000];

    systemd.services.syncthing.after = ["network-online.target"];
    systemd.services.syncthing.wants = ["network-online.target"];
  };
}
