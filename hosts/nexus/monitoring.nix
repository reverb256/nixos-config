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

      # Promtail - ship logs to Loki on sentry
      promtail.enable = true;
      promtail.lokiUrl = "http://10.1.1.140:3100/loki/api/v1/push";
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
