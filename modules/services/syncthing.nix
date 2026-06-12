{
  config,
  lib,
  ...
}: let
  cfg = config.services.syncthing-cluster;
in {
  options.services.syncthing-cluster = {
    enable = lib.mkEnableOption "Syncthing P2P file sync for cluster";
  };

  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = lib.mkDefault true;
      user = "j_kro";
      dataDir = "/var/lib/syncthing";
      configDir = "/var/lib/syncthing/.config/syncthing";

      openDefaultPorts = true;

      settings = {
        devices = {
          zephyr = {
            id = "SLDVJQT-WB37JTE-UWIXCZW-3A6HZFK-MJ5CAFC-MV5AQXV-25PM6AC-WZSVBAC";
            addresses = ["dynamic"];
            autoAcceptFolders = false;
          };
          nexus = {
            id = "GLYKX2M-6Q3TM3W-FJ727N5-76OHMGB-5BDVI7R-A6VXEFO-E32XYRP-YVWNSQ5";
            addresses = ["dynamic"];
            autoAcceptFolders = false;
          };
          forge = {
            id = "ZITBGH3-PK3SE37-P4FH7WG-ZS6OQKY-FWAN73V-XWBI6C3-VUSX42H-HT24ZAE";
            addresses = ["dynamic"];
            autoAcceptFolders = false;
          };
          sentry = {
            id = "C6H7ICX-5QYPNFO-ORD4A3M-S2BEQRZ-CK2YDJM-XXW7TOX-JAAKSOT-JWF5UAK";
            addresses = ["dynamic"];
            autoAcceptFolders = false;
          };
        };

        folders = {
          "nixos-config" = {
            path = "/etc/nixos";
            devices = ["zephyr" "nexus" "forge" "sentry"];
            type = "sendreceive";
            ignorePerms = false;
            fsWatcherEnabled = true;
            autoNormalize = true;
            rescanIntervalS = 60;
            versioning = {
              type = "staggered";
              params = {
                cleanInterval = "3600";
                maxAge = "86400";
              };
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

    systemd.services.syncthing-init = {
      serviceConfig = {
        SuccessExitStatus = "0 5";
      };
      unitConfig = {
        StartLimitIntervalSec = 0;
      };
      onFailure = lib.mkForce [];
    };
  };
}
