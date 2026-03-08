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

    redisAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:6379";
      description = "Redis server address";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.redis = {
      enable = true;
      inherit (cfg) redisAddr;
      port = 9121;
    };

    # Open firewall for Prometheus scraping
    networking.firewall.allowedTCPPorts = [9121];
  };
}
