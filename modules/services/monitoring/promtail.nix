# Promtail Log Shipping Agent
# Ships logs from journald to Loki
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.promtail;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.services.promtail = {
    enable = mkEnableOption "Promtail log shipping agent";

    lokiUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:3100/loki/api/v1/push";
      description = "Loki server URL for log shipping";
    };

    configuration = mkOption {
      type = types.attrs;
      default = { };
      description = "Additional Promtail configuration";
    };
  };

  config = mkIf cfg.enable {
    services.promtail = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 28183;
          grpc_listen_port = 0;
        };

        clients = [
          {
            url = cfg.lokiUrl;
          }
        ];

        # Scrape journald logs
        scrape_configs = [
          {
            job_name = "journald";
            journal = {
              max_age = "168h"; # 7 days
              labels = {
                job = "systemd-journal";
                host = "${config.networking.hostName}";
                cluster = "reverb-os";
              };
            };
            relabel_configs = [
              {
                source_labels = [ "__journal__systemd_unit" ];
                target_label = "unit";
              }
              {
                source_labels = [ "__journal__hostname" ];
                target_label = "host";
              }
              {
                source_labels = [ "__journal__priority_keyword" ];
                target_label = "level";
              }
            ];
          }
        ];
      }
      // cfg.configuration;
    };

    # Create state directory
    systemd.tmpfiles.settings."promtail" = {
      "/var/lib/promtail" = {
        d = {
          user = "promtail";
          group = "promtail";
          mode = "0750";
        };
      };
      "/var/lib/promtail/positions" = {
        d = {
          user = "promtail";
          group = "promtail";
          mode = "0750";
        };
      };
    };

    # User and group
    users.users.promtail = {
      isSystemUser = true;
      group = "promtail";
      description = "Promtail log shipping agent";
    };
    users.groups.promtail = { };
  };
}
