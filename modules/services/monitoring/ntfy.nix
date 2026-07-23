# ntfy Push Notification Service
# Simple phone push for Prometheus Alertmanager alerts
# Deployed on Sentry alongside Alertmanager
{ config, lib, pkgs, ... }: let
  cfg = config.services.monitoring.ntfy;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.monitoring.ntfy = {
    enable = mkEnableOption "ntfy push notification service";
    port = mkOption { type = types.port; default = 9099; };
    topic = mkOption {
      type = types.str;
      default = "cluster-alerts";
      description = "Default topic for cluster alerts";
    };
  };

  config = mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "http://127.0.0.1:${toString cfg.port}";
        listen-http = "127.0.0.1:${toString cfg.port}";
        # No auth required for local webhook (trusted network)
        auth-default-access = "read-write";
        cache-file = "/var/lib/ntfy/cache.db";
        # Keep notifications for 48h
        visitor-subscription-ttl = "48h";
      };
    };

    # Wire Alertmanager's local webhook to ntfy
    services.prometheus.alertmanager.configuration.receivers = let
      base = {
        name = "default";
        webhook_configs = [{
          url = "http://127.0.0.1:${toString cfg.port}/${cfg.topic}";
          send_resolved = true;
        }];
      };
    in [ base ];

    # Open for localhost only
    networking.firewall.allowedTCPPorts = [];
  };
}
