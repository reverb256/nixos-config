# AlertManager Service
# Routes and manages alerts from Prometheus
{
  config,
  lib,
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

    # Email notification configuration (optional, requires SMTP)
    email = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable email notifications (requires SMTP password)";
      };

      smtphost = lib.mkOption {
        type = lib.types.str;
        default = "localhost:587";
        description = "SMTP server address";
      };

      from = lib.mkOption {
        type = lib.types.str;
        default = "alertmanager@localhost";
        description = "From email address";
      };

      to = lib.mkOption {
        type = lib.types.str;
        default = "admin@reverb256.ca";
        example = "admin@example.com";
        description = "Recipient email address for alerts";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression "/run/agenix/alertmanager-smtp-password";
        description = "Path to file containing SMTP password";
      };
    };

    # Webhook notification configuration (local, no auth required)
    webhook = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable local webhook notifications (no password required)";
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:9099/alerts";
        description = "Local webhook URL for alert notifications";
      };
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
        global =
          {
            smtp_smarthost = cfg.email.smtphost;
            smtp_from = cfg.email.from;
          }
          // lib.optionalAttrs cfg.email.enable {
            smtp_auth_username = cfg.email.from;
            smtp_auth_password_file = cfg.email.passwordFile;
            smtp_require_tls = true;
          }
          // lib.optionalAttrs (!cfg.email.enable) {
            smtp_require_tls = false;
          };

        # Route all alerts to default receivers
        route = {
          receiver = "default";
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
          group_by = ["alertname" "cluster"];
        };

        # Default receiver(s)
        receivers = let
          baseReceiver = {
            name = "default";
            # Local webhook (no auth required)
            webhook_configs = lib.optionals cfg.webhook.enable [
              {
                inherit (cfg.webhook) url;
                send_resolved = true;
              }
            ];
          };
          receiverWithEmail =
            baseReceiver
            // {
              email_configs = [
                {
                  inherit (cfg.email) to;
                  inherit (cfg.email) from;
                  smarthost = cfg.email.smtphost;
                  auth_username = cfg.email.from;
                  auth_password_file = cfg.email.passwordFile;
                  require_tls = true;
                }
              ];
            };
        in
          if cfg.email.enable
          then [receiverWithEmail]
          else [baseReceiver];
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
