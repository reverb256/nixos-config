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
    services.monitoring = {
      prometheus = lib.mkIf cfg.prometheus.enable {
        enable = true;
        retentionDays = cfg.prometheus.retentionDays;
      };

      alertmanager = lib.mkIf cfg.alertmanager.enable {
        enable = true;
      };

      node-exporter = lib.mkIf cfg.nodeExporter.enable {
        enable = true;
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = lib.mkOptionDefault (
      lib.optional cfg.prometheus.enable ports.prometheus
      ++ lib.optional cfg.alertmanager.enable ports.alertmanager
    );
  };
}
