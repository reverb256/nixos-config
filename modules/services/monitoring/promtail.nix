# Promtail Log Agent
# Ships systemd journals to Loki for centralized logging
{
  config,
  lib,
  ...
}: let
  cfg = config.services.monitoring.promtail;
  currentHost = config.networking.hostName;
  clusterConfig = config.networking.cluster;
in {
  options.services.monitoring.promtail = {
    enable = lib.mkEnableOption "Promtail log agent for Loki";

    lokiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:3100";
      description = "Loki server URL";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/promtail";
      description = "Directory for Promtail data";
    };
  };

  config = lib.mkIf cfg.enable {
    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 9080;
          grpc_listen_port = 0;
        };

        # Loki client configuration
        client = {
          url = cfg.lokiUrl;
        };

        # Scrape systemd journals with Golden Signals labels
        scrape_configs = [
          {
            job_name = "systemd-journal";
            journal = {
              path = "/var/log/journal";
              matches = "_TRANSPORT=syslog";
              json = true;
              labels = {
                cluster = "nixos-cluster";
                host = "${currentHost}";
                environment = "production";
                network = clusterConfig.subnet;
              };
            };
            relabel_configs = [
              # Extract systemd unit name
              {
                source_labels = ["__journal__systemd_unit"];
                target_label = "unit";
                regex = "(.*)\\.service";
              }
              # Extract priority level
              {
                source_labels = ["__journal_priority"];
                target_label = "level";
              }
              # Extract boot_id for session tracking
              {
                source_labels = ["__journal_boot_id"];
                target_label = "boot_id";
              }
              # Drop noisy low-priority logs (debug)
              {
                source_labels = ["__journal_priority"];
                regex = "7";
                action = "drop";
              }
              # Add hostname label
              {
                target_label = "hostname";
                replacement = "${currentHost}";
              }
            ];
          }
        ];
      };
    };

    # Create data directory
    systemd.tmpfiles.settings."promtail" = {
      "${cfg.dataDir}" = {
        d = {
          user = "promtail";
          group = "promtail";
          mode = "0750";
        };
      };
      "${cfg.dataDir}/positions" = {
        d = {
          user = "promtail";
          group = "promtail";
          mode = "0750";
        };
      };
    };

    # Network configuration
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [9080];
  };
}
