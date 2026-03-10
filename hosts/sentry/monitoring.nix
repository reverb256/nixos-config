# Sentry Monitoring Configuration
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # SERVICES CONFIGURATION
  services = {
    # Monitoring exporters
    monitoring = {
      # Node exporter for system metrics
      node-exporter.enable = true;

      # SMART exporter for disk health monitoring
      smart-exporter.enable = true;

      # Promtail - ship logs to Loki on zephyr
      promtail.enable = true;
      promtail.lokiUrl = "http://100.81.182.5:3100"; # Zephyr's Tailscale IP
    };

    # Note: Sentry has no GPUs, no GPU exporters needed

    # Mining exporter for CPU mining metrics
    mining-exporter.enable = true;
  };
}
