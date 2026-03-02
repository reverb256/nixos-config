# Prometheus Monitoring Server
# Centralized metrics collection for NixOS cluster
# Should be deployed on a dedicated monitoring node
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.monitoring.prometheus;
in
{
  options.services.monitoring.prometheus = {
    enable = lib.mkEnableOption "Prometheus monitoring server";

    retentionDays = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Number of days to retain metrics data";
    };

    scrapeInterval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = "Default scrape interval";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for Prometheus server";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = cfg.port;
      listenAddress = "127.0.0.1"; # Localhost only, use nginx for external access

      # Data retention
      retentionTime = "${toString cfg.retentionDays}d";

      # Global configuration
      globalConfig = {
        scrape_interval = cfg.scrapeInterval;
        evaluation_interval = "1m";
      };

      # Scrape configurations - add node exporters as needed
      scrapeConfigs = [
        # Node exporter for all hosts
        {
          job_name = "node";
          static_configs = [
            {
              targets = [
                "10.1.1.110:9100"  # zephyr
                "10.1.1.120:9100"  # nexus
                "10.1.1.130:9100"  # forge
                "10.1.1.140:9100"  # sentry
              ];
              labels = {
                environment = "production";
              };
            }
          ];
          relabel_configs = [
            {
              source_labels = ["__address__"];
              regex = "([^:]+):.*";
              replacement = "\${1}";
              target_label = "host";
            }
          ];
        }

        # Prometheus self-monitoring
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = ["127.0.0.1:${toString cfg.port}"];
            }
          ];
        }

        # Llama.cpp AI Inference Server (Zephyr)
        {
          job_name = "llama-server";
          static_configs = [
            {
              targets = ["10.1.1.110:8001"];
              labels = {
                host = "zephyr";
                service = "llama-server";
              };
            }
          ];
          scheme = "http";
          metrics_path = "/metrics";
        }
      ];
    };

    # Create prometheus user (systemd service runs as prometheus by default)
    users.users.prometheus = {
      isSystemUser = true;
      group = "prometheus";
    };
    users.groups.prometheus = {};

    # Open firewall for internal access
    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
