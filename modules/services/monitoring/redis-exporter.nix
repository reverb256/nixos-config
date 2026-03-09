# Redis Exporter for Prometheus
# Collects Redis metrics for monitoring cache performance
# Useful for AI Gateway's Redis (rate limiting, semantic cache)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.monitoring.redis-exporter;
in {
  options.services.monitoring.redis-exporter = {
    enable = lib.mkEnableOption "Redis exporter for Prometheus";
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.redis = {
      enable = true;
      port = 9121;
    };

    # Open firewall for Prometheus scraping
    networking.firewall.allowedTCPPorts = [9121];
  };
}
