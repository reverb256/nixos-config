# Zephyr Monitoring Configuration
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # Node exporter for system metrics
  services.monitoring.node-exporter.enable = true;

  # GPU metrics exporter (NVIDIA RTX 3090 + 3060 Ti)
  services.gpu-exporters = {
    enable = true;
    nvidia.enable = true; # RTX 3090 + 3060 Ti
    amd.enable = false;
  };

  # Mining exporter (for mining operations on zephyr)
  services.mining-exporter.enable = true;
}
