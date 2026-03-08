# Prometheus Monitoring Server
# Centralized metrics collection for the NixOS cluster
# Should be deployed on sentry (monitoring node)
{
  config,
  lib,
  ...
}: let
  cfg = config.services.monitoring.prometheus;
  # Use centralized network constants to avoid duplication
  inherit (config.networking.cluster) ports;
in {
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
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = ports.prometheus;
      listenAddress = "127.0.0.1"; # Localhost only, use nginx for external access

      # Data retention
      retentionTime = "${toString cfg.retentionDays}d";

      # Global configuration
      globalConfig = {
        scrape_interval = cfg.scrapeInterval;
        evaluation_interval = "1m";
      };

      # AlertManager configuration
      alertmanagers = [
        {
          static_configs = [
            {
              targets = ["127.0.0.1:${toString ports.alertmanager}"];
            }
          ];
        }
      ];

      # Alert rules (inline for NixOS)
      ruleFiles = [ ];
      # Note: AlertManager integration is configured via alertmanagers option above
      # Custom alert rules should be added via services.prometheus.ruleFiles

      # Scrape configurations for cluster nodes
      scrapeConfigs = [
        # Node exporter for all hosts
        {
          job_name = "node";
          static_configs = [
            {
              targets = [
                "zephyr:${toString ports.node-exporter}"
                "nexus:${toString ports.node-exporter}"
                "forge:${toString ports.node-exporter}"
                "sentry:${toString ports.node-exporter}"
              ];
              labels = {
                environment = "production";
              };
            }
          ];
        }

        # Mining metrics exporter for all hosts
        {
          job_name = "mining";
          static_configs = [
            {
              targets = [
                "zephyr:9105"
                "nexus:9105"
                "forge:9105"
                "sentry:9105"
              ];
              labels = {
                environment = "production";
              };
            }
          ];
        }

        # NVIDIA GPU metrics (for hosts with NVIDIA GPUs)
        {
          job_name = "nvidia";
          static_configs = [
            {
              targets = [
                "zephyr:9400"
                "nexus:9400"
                "forge:9400"
              ];
            }
          ];
        }

        # Redis metrics (AI Gateway cache)
        {
          job_name = "redis";
          static_configs = [
            {
              targets = ["zephyr:9121"];
              labels = {
                role = "ai-gateway-cache";
              };
            }
          ];
        }

        # Prometheus self-monitoring
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = ["localhost:${toString ports.prometheus}"];
            }
          ];
        }

        # AlertManager self-monitoring
        {
          job_name = "alertmanager";
          static_configs = [
            {
              targets = ["localhost:${toString ports.alertmanager}"];
            }
          ];
        }

        # Grafana metrics
        {
          job_name = "grafana";
          static_configs = [
            {
              targets = ["localhost:${toString ports.grafana}"];
            }
          ];
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
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      ports.prometheus
    ];
  };
}
