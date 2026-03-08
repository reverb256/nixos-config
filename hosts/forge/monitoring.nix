# Forge Monitoring Configuration
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # Node exporter for system metrics
  services.monitoring.node-exporter.enable = true;

  # SMART exporter for disk health monitoring
  services.monitoring.smart-exporter.enable = true;

  # GPU exporters for RTX 4060 (2x NVIDIA) + RX 5700 XT (2x AMD)
  # Note: GPU metrics are already exported via nvidia-exporter on port 9400
  # This is configured via hardware.profiles.nvidia

  # Mining exporter for xmrig/lolminer metrics
  # Note: Mining metrics are exported via the mining-exporter module
  # Enable if you want to track hashrate, power usage, etc.
  # services.mining-exporter.enable = true;
}
