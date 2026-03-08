# Sentry Monitoring Configuration
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # Node exporter for system metrics
  services.monitoring.node-exporter.enable = true;

  # SMART exporter for disk health monitoring
  services.monitoring.smart-exporter.enable = true;

  # GPU exporters - AMD RX 5600 XT monitoring
  services.gpu-exporters.enable = true;
  services.gpu-exporters.amd.enable = true;

  # Mining exporter for CPU mining metrics
  services.mining-exporter.enable = true;
}
