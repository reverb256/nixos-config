# Sentry Monitoring Configuration
{...}: {
  imports = [
    # ../../modules/services/monitoring/default.nix  # TEMP: Compatibility issues
  ];

  # Node exporter for system metrics
  # services.monitoring.node-exporter.enable = true;

  # GPU exporters - AMD RX 5600 XT monitoring (now with ROCm)
  # services.gpu-exporters = {
  #   enable = true;
  #   nvidia.enable = false;
  #   amd.enable = true;
  # };

  # Mining exporter for CPU mining metrics
  # services.mining-exporter.enable = true;
}
