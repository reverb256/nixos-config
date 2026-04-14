{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.programs.systems-intelligence-plasmoid;

  plasmoidName = "org.revervos.systems-intelligence";
  plasmoidSrc = ../../plasmoids/systems-intelligence;
in {
  options.programs.systems-intelligence-plasmoid = {
    enable = lib.mkEnableOption "Systems Intelligence Plasma Plasmoid - Cluster monitoring widget";

    prometheusUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:9090";
      description = "Prometheus server URL for metrics";
    };

    refreshInterval = lib.mkOption {
      type = lib.types.int;
      default = 5000;
      description = "Refresh interval in milliseconds";
    };

    clusterNodes = lib.mkOption {
      type = lib.types.str;
      default = "zephyr,nexus,forge,sentry";
      description = "Comma-separated list of cluster node names";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User to install the plasmoid for";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.settings."plasmoid-${cfg.user}" = {
      "/home/${cfg.user}/.local/share/plasma/plasmoids/${plasmoidName}" = {
        d = {
          inherit (cfg) user;
          group = "users";
          mode = "0755";
        };
      };
    };

    systemd.services."plasmoid-${cfg.user}" = {
      description = "Install Systems Intelligence Plasmoid for ${cfg.user}";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
      };
      script = ''
        mkdir -p ~/.local/share/plasma/plasmoids/${plasmoidName}
        cp -r ${plasmoidSrc}/* ~/.local/share/plasma/plasmoids/${plasmoidName}/
        chmod -R 0755 ~/.local/share/plasma/plasmoids/${plasmoidName}
      '';
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "install-plasmoid" ''
        mkdir -p ~/.local/share/plasma/plasmoids/${plasmoidName}
        cp -r ${plasmoidSrc}/* ~/.local/share/plasma/plasmoids/${plasmoidName}/
        chmod -R 0755 ~/.local/share/plasma/plasmoids/${plasmoidName}
        echo "Plasmoid installed. Reload Plasma widgets with: kquitapp5 plasmashell && kstart5 plasmashell"
      '')
    ];
  };
}
