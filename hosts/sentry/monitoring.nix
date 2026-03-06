# Sentry Monitoring Configuration
{ config, pkgs, ... }: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # Node exporter for system metrics
  services.monitoring.node-exporter.enable = true;

  # GPU exporters - currently disabled (AMD support incomplete)
  services.gpu-exporters.enable = false;

  # Mining exporter for CPU mining metrics
  services.mining-exporter.enable = true;
}
