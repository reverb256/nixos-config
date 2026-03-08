# Systems Intelligence Plasma Plasmoid
# Cluster-wide monitoring widget for Plasma 6 desktop
# Shows node health, resource usage, GPU stats, alerts, and mining status
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.programs.systems-intelligence-plasmoid;

  # Plasmoid source location
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
    # Install plasmoid system-wide
    environment.systemPackages = [
      (pkgs.runCommand "${plasmoidName}" {} ''
        mkdir -p $out/share/plasma/plasmoids/${plasmoidName}
        cp -r ${plasmoidSrc}/* $out/share/plasma/plasmoids/${plasmoidName}/
      '')
    ];

    # Ensure plasmoid can be discovered
    environment.pathsToLink = ["/share/plasma/plasmoids"];
  };
}
