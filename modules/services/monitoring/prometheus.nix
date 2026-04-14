{
  config,
  lib,
  ...
}:
let
  cfg = config.services.monitoring.prometheus;
  inherit (config.networking.cluster) ports;
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

    enableAlertRules = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable cluster alert rules";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = ports.prometheus;
      listenAddress = "127.0.0.1";

      retentionTime = "${toString cfg.retentionDays}d";

      globalConfig = {
        scrape_interval = cfg.scrapeInterval;
        evaluation_interval = "1m";
      };

      alertmanagers = [
        {
          static_configs = [
            {
              targets = [ "127.0.0.1:${toString ports.alertmanager}" ];
            }
          ];
        }
      ];


      scrapeConfigs = [
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



        {
          job_name = "redis";
          static_configs = [
            {
              targets = [ "zephyr:9121" ];
              labels = {
                role = "ai-gateway-cache";
              };
            }
          ];
        }

        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = [ "localhost:${toString ports.prometheus}" ];
            }
          ];
        }

        {
          job_name = "alertmanager";
          static_configs = [
            {
              targets = [ "localhost:${toString ports.alertmanager}" ];
            }
          ];
        }

        {
          job_name = "grafana";
          static_configs = [
            {
              targets = [ "localhost:${toString ports.grafana}" ];
            }
          ];
        }

        {
          job_name = "garage";
          static_configs = [
            {
              targets = [
                "zephyr:3902"
                "nexus:3902"
                "sentry:3902"
              ];
              labels = {
                role = "object-storage";
                tier = "3-node-cluster";
              };
            }
          ];
          metrics_path = "/metrics";
          params = {
            token = [ "garage_metrics_token" ];
          };
        }

        {
          job_name = "caddy-ingress";
          static_configs = [
            {
              targets = [
                "caddy-ingress-controller-metrics.ingress-system.svc.cluster.local:9765"
              ];
              labels = {
                role = "ingress";
                tier = "kubernetes";
              };
            }
          ];
          metrics_path = "/metrics";
          scheme = "http";
        }
      ];
    };

    users.users.prometheus = {
      isSystemUser = true;
      group = "prometheus";
    };
    users.groups.prometheus = { };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      ports.prometheus
    ];
  };
}
