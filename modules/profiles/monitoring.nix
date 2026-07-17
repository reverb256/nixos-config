# Monitoring Profile Module
#
# Reusable profile for monitoring services (Prometheus, Grafana, AlertManager)
# Enables easy deployment of monitoring stack on specific nodes
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.profiles.monitoring;
  inherit (config.networking.cluster) ports;
in {
  options.profiles.monitoring = {
    enable = lib.mkEnableOption "Monitoring stack (Prometheus, Grafana, AlertManager)";

    prometheus = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable Prometheus metrics server";
      };

      retentionDays = lib.mkOption {
        type = lib.types.int;
        default = 15;
        description = "Number of days to retain metrics data";
      };
    };

    grafana = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable Grafana dashboard server";
      };
    };

    alertmanager = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Enable AlertManager alert routing";
      };
    };

    nodeExporter = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Prometheus node exporter (metrics collection)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable monitoring services
    services.monitoring = {
      # Prometheus configuration
      prometheus = lib.mkIf cfg.prometheus.enable {
        enable = true;
        retentionDays = cfg.prometheus.retentionDays;
      };

      # Grafana configuration
      grafana = lib.mkIf cfg.grafana.enable {
        enable = true;
      };

      # AlertManager configuration
      alertmanager = lib.mkIf cfg.alertmanager.enable {
        enable = true;
      };

      # Node exporter (enabled by default)
      node-exporter = lib.mkIf cfg.nodeExporter.enable {
        enable = true;
      };
    };

    # Firewall configuration - allow Tailscale access to monitoring ports
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.mkOptionDefault (
      lib.optional cfg.prometheus.enable ports.prometheus
      ++ lib.optional cfg.grafana.enable ports.grafana
      ++ lib.optional cfg.alertmanager.enable ports.alertmanager
    );
  };
}
