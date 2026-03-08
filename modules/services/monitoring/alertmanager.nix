# AlertManager Service
# Routes and manages alerts from Prometheus
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.monitoring.alertmanager;
  inherit (config.networking.cluster) ports;
in {
  options.services.monitoring.alertmanager = {
    enable = lib.mkEnableOption "AlertManager alert routing service";

    retentionDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Number of days to retain alert history";
    };

    externalUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:${toString ports.alertmanager}";
      description = "External URL for AlertManager";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.alertmanager = {
      enable = true;
      port = ports.alertmanager;
      listenAddress = "127.0.0.1";

      webExternalUrl = cfg.externalUrl;

      # Basic configuration
      configuration = {
        global = {
          # SMTP not configured - add email config later if needed
          smtp_smarthost = "localhost:587";
          smtp_from = "alertmanager@localhost";
          smtp_require_tls = false;
        };

        # Route all alerts to a default receiver
        route = {
          receiver = "default";
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
          group_by = ["alertname" "cluster"];
        };

        # Default receiver - currently logs to webhook
        receivers = [
          {
            name = "default";
            webhook_configs = [
              {
                url = "http://127.0.0.1:9093/-/alerts";
                send_resolved = true;
              }
            ];
          }
        ];
      };
    };

    # Open firewall for internal Tailscale access
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      ports.alertmanager
    ];

    # Add user
    users.users.alertmanager = {
      isSystemUser = true;
      group = "alertmanager";
    };
    users.groups.alertmanager = {};
  };
}
