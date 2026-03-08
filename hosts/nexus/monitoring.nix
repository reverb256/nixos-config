# Nexus Monitoring Configuration
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # Node exporter for system metrics
  services.monitoring.node-exporter.enable = true;

  # SMART exporter for disk health monitoring
  services.monitoring.smart-exporter.enable = true;

  # NVIDIA GPU exporter for RTX 3060 Ti (2x GPUs)
  services.gpu-exporters.enable = true;
  services.gpu-exporters.nvidia.enable = true;

  # Mining exporter for xmrig/lolminer metrics
  services.mining-exporter.enable = true;

  # Promtail - ship logs to Loki on zephyr
  services.monitoring.promtail.enable = true;
  services.monitoring.promtail.lokiUrl = "http://100.81.182.5:3100";  # Zephyr's Tailscale IP
}
