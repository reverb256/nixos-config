# Forge Monitoring Configuration
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # Node exporter for system metrics
  services.monitoring.node-exporter.enable = true;

  # GPU exporters for RTX 4060 (2x NVIDIA) + RX 5700 XT (2x AMD)
  services.gpu-exporters = {
    enable = true;
    nvidia.enable = true; # 2x RTX 4060
    amd.enable = true; # 2x RX 5700 XT
  };

  # Mining exporter for xmrig/lolminer metrics
  services.mining-exporter.enable = true;
}
