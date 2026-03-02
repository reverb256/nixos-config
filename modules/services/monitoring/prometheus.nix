# Prometheus Monitoring Server
# Centralized metrics collection for the NixOS cluster
# Should be deployed on sentry (monitoring node)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.monitoring.prometheus;
  # Use centralized network constants to avoid duplication
  hosts = config.networking.cluster.hosts;
  ports = config.networking.cluster.ports;
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

      # Scrape configurations for cluster nodes
      scrapeConfigs = [
        # Node exporter for all hosts
        {
          job_name = "node";
          static_configs = [
            {
              targets = [
                "${hosts.zephyr.ip}:${toString ports.node-exporter}"
                "${hosts.nexus.ip}:${toString ports.node-exporter}"
                "${hosts.forge.ip}:${toString ports.node-exporter}"
                "${hosts.sentry.ip}:${toString ports.node-exporter}"
              ];
              labels = {
                environment = "production";
              };
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              regex = "([^:]+):.*";
              replacement = "\${1}";
              target_label = "host";
            }
          ];
        }

        # Mining metrics exporter for all hosts
        {
          job_name = "mining";
          static_configs = [
            {
              targets = [
                "${hosts.zephyr.ip}:9105"
                "${hosts.nexus.ip}:9105"
                "${hosts.forge.ip}:9105"
                "${hosts.sentry.ip}:9105"
              ];
              labels = {
                environment = "production";
              };
            }
          ];
          relabel_configs = [
            {
              source_labels = [ "__address__" ];
              regex = "([^:]+):.*";
              replacement = "\${1}";
              target_label = "host";
            }
          ];
        }

        # NVIDIA GPU metrics (for hosts with NVIDIA GPUs)
        {
          job_name = "nvidia";
          static_configs = [
            {
              targets = [
                "${hosts.zephyr.ip}:9400"
                "${hosts.nexus.ip}:9400"
                "${hosts.forge.ip}:9400"
              ];
            }
          ];
        }

        # Prometheus self-monitoring
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = [ "127.0.0.1:${toString ports.prometheus}" ];
            }
          ];
        }
      ];
    };

    # Alertmanager configuration - temporarily disabled
    # services.prometheus.alertmanager = {
    #   enable = true;
    #   listenAddress = "127.0.0.1";
    #   port = 9093;
    #   configuration = {
    #     global = {
    #       resolve_timeout = "5m";
    #     };
    #     route = {
    #       group_by = ["alertname" "severity"];
    #       group_wait = "30s";
    #       group_interval = "5m";
    #       repeat_interval = "4h";
    #       receiver = "default";
    #     };
    #     receivers = [
    #       {
    #         name = "default";
    #         # Add notification methods here (email, slack, etc.)
    #       }
    #     ];
    #   };
    # };

    # Create prometheus user (systemd service runs as prometheus by default)
    users.users.prometheus = {
      isSystemUser = true;
      group = "prometheus";
    };
    users.groups.prometheus = { };

    # Open firewall for internal access
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      ports.prometheus
    ];
  };
}
