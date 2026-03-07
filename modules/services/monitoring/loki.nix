# Loki Log Aggregation Service
# Centralized log storage with Grafana integration
{
  config,
  lib,
  ...
}: let
  cfg = config.services.loki;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in {
  options.services.loki = {
    enable = mkEnableOption "Loki log aggregation server";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/loki";
      description = "Directory for Loki data storage";
    };

    retentionPeriod = mkOption {
      type = types.str;
      default = "30d";
      description = "Log retention period (e.g., '30d', '168h')";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to listen on";
    };

    port = mkOption {
      type = types.port;
      default = 3100;
      description = "Port for Loki HTTP server";
    };
  };

  config = mkIf cfg.enable {
    services.loki = {
      enable = true;
      configuration = {
        server.http_listen_port = cfg.port;
        server.http_listen_address = cfg.listenAddress;

        # Data storage
        common = {
          storage.filesystem = {
            chunks_directory = "${cfg.dataDir}/chunks";
            rules_directory = "${cfg.dataDir}/rules";
          };
          replication_factor = 1;
        };

        # Schema configuration
        schema_config = {
          configs = [
            {
              from = "2024-01-01";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
        };

        # Retention policy
        limits_config = {
          retention_period = cfg.retentionPeriod;
          retention_stream_max_age = cfg.retentionPeriod;
          per_stream_rate_limit = "10MB";
          per_stream_rate_limit_burst = "20MB";
        };

        # Ingester configuration
        ingester = {
          chunk_idle_period = "1h";
          max_chunk_age = "2h";
          target_chunk_size = 1048576; # 1MB
        };

        # Limits
        compactor = {
          working_directory = "${cfg.dataDir}/compactor";
          retention_enabled = true;
          delete_request_cancel_period = "24h";
          compaction_interval = "10m";
        };

        # Ruler for alerting on logs
        ruler = {
          enable = true;
          enable_alertmanager = true;
          alertmanager_url = "http://127.0.0.1:9093";
          storage = {
            type = "local";
            local = {
              directory = "${cfg.dataDir}/rules";
            };
          };
        };
      };
    };

    # Create data directories
    systemd.tmpfiles.settings."loki" = {
      "${cfg.dataDir}" = {
        d = {
          user = "loki";
          group = "loki";
          mode = "0750";
        };
      };
      "${cfg.dataDir}/chunks" = {
        d = {
          user = "loki";
          group = "loki";
          mode = "0750";
        };
      };
      "${cfg.dataDir}/rules" = {
        d = {
          user = "loki";
          group = "loki";
          mode = "0750";
        };
      };
      "${cfg.dataDir}/compactor" = {
        d = {
          user = "loki";
          group = "loki";
          mode = "0750";
        };
      };
    };

    # User and group
    users.users.loki = {
      isSystemUser = true;
      group = "loki";
      description = "Loki log aggregation service";
    };
    users.groups.loki = {};

    # Firewall
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [cfg.port];
  };
}
