# Nexus Monitoring Configuration
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # Services configuration
  services = {
    monitoring = {
      # Node exporter for system metrics
      node-exporter.enable = true;

      # SMART exporter for disk health monitoring
      smart-exporter.enable = true;

      # Promtail - ship logs to Loki on zephyr
      promtail.enable = true;
      promtail.lokiUrl = "http://100.81.182.5:3100"; # Zephyr's Tailscale IP
    };

    # NVIDIA GPU exporter for RTX 3060 Ti (2x GPUs)
    gpu-exporters = {
      enable = true;
      nvidia.enable = true;
    };

    # Mining exporter for xmrig/lolminer metrics
    mining-exporter.enable = true;
  };
}
