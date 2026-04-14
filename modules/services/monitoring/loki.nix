{
  config,
  lib,
  ...
}: let
  cfg = config.services.monitoring.loki;
in {
  options.services.monitoring.loki = {
    enable = lib.mkEnableOption "Loki log aggregation server";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/loki";
      description = "Directory for Loki data storage";
    };

    retentionPeriod = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Log retention period (e.g., '30d', '168h')";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to listen on";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3100;
      description = "Port for Loki HTTP server";
    };
  };

  config = lib.mkIf cfg.enable {
    services.loki = {
      enable = true;
      configuration = {
        server.http_listen_port = cfg.port;
        server.http_listen_address = cfg.listenAddress;

        common = {
          path_prefix = cfg.dataDir;
          storage.filesystem = {
            chunks_directory = "${cfg.dataDir}/chunks";
            rules_directory = "${cfg.dataDir}/rules";
          };
          replication_factor = 1;
        };

        schema_config = {
          configs = [
            {
              from = "2024-01-01";
              store = "boltdb-shipper";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
        };

        storage_config = {
          boltdb_shipper = {
            active_index_directory = "${cfg.dataDir}/boltdb-shipper/index";
            cache_location = "${cfg.dataDir}/boltdb-shipper/cache";
          };
        };

        limits_config = {
          retention_period = cfg.retentionPeriod;
          per_stream_rate_limit = "10MB";
          per_stream_rate_limit_burst = "20MB";
          allow_structured_metadata = false;
        };

        ingester = {
          chunk_idle_period = "1h";
          max_chunk_age = "2h";
          lifecycler = {
            ring = {
              kvstore = {
                store = "inmemory";
              };
            };
          };
        };

        compactor = {
          working_directory = "${cfg.dataDir}/compactor";
          retention_enabled = true;
          delete_request_cancel_period = "24h";
          compaction_interval = "10m";
          delete_request_store = "filesystem";
        };

        ruler = {
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
      "${cfg.dataDir}/boltdb-shipper" = {
        d = {
          user = "loki";
          group = "loki";
          mode = "0750";
        };
      };
      "${cfg.dataDir}/boltdb-shipper/index" = {
        d = {
          user = "loki";
          group = "loki";
          mode = "0750";
        };
      };
      "${cfg.dataDir}/boltdb-shipper/cache" = {
        d = {
          user = "loki";
          group = "loki";
          mode = "0750";
        };
      };
    };


    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [cfg.port];
  };
}
