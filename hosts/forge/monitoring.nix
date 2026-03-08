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
  services.gpu-exporters.enable = true;
  services.gpu-exporters.nvidia.enable = true;
  services.gpu-exporters.amd.enable = true;

  # Mining exporter for xmrig/lolminer metrics
  services.mining-exporter.enable = true;
}
