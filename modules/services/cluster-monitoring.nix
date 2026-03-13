# Cluster Monitoring Configuration
# Centralized monitoring setup for all cluster nodes
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.clusterMonitoring = {
    enable = mkEnableOption "Cluster monitoring configuration";

    lokiUrl = mkOption {
      type = types.str;
      default = "http://100.81.182.5:3100"; # Zephyr's Tailscale IP
      description = "Loki server URL for Promtail logs";
    };

    exporters = {
      node = mkOption {
        type = types.bool;
        default = true;
        description = "Enable node exporter (system metrics)";
      };

      smart = mkOption {
        type = types.bool;
        default = true;
        description = "Enable SMART exporter (disk health)";
      };

      gpu = mkOption {
        type = types.bool;
        default = false;
        description = "Enable GPU exporter (NVIDIA/AMD metrics)";
      };

      mining = mkOption {
        type = types.bool;
        default = false;
        description = "Enable mining exporter (XMRig metrics)";
      };
    };

    logging = {
      promtail = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Promtail log shipping";
      };
    };
  };

  config = mkIf config.services.clusterMonitoring.enable {
    services.monitoring = {
      # Node exporter for system metrics
      node-exporter.enable = config.services.clusterMonitoring.exporters.node;

      # SMART exporter for disk health
      smart-exporter.enable = config.services.clusterMonitoring.exporters.smart;

      # Promtail - ship logs to Loki
      promtail = mkIf config.services.clusterMonitoring.logging.promtail {
        enable = true;
        inherit (config.services.clusterMonitoring) lokiUrl;
      };
    };
  };
}
