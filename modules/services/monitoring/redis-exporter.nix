{
  config,
  lib,
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

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [9121];
  };
}
