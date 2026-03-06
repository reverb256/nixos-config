# Nexus Monitoring Configuration
{ config, pkgs, ... }: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # Node exporter for system metrics
  services.monitoring.node-exporter.enable = true;

  # NVIDIA GPU exporter for RTX 3060 Ti (2x GPUs)
  services.gpu-exporters = {
    enable = true;
    nvidia.enable = true;
    amd.enable = false;
  };

  # Mining exporter for xmrig/lolminer metrics
  services.mining-exporter.enable = true;
}
