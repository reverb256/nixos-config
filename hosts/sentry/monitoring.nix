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
  # Note: AMD GPU metrics are exported via amdgpu exporter
  # This is configured via hardware.profiles.amdgpu

  # Mining exporter for CPU mining metrics
  # Note: Mining metrics are exported via the mining-exporter module
  # Enable if you want to track hashrate, power usage, etc.
  # services.mining-exporter.enable = true;
}
