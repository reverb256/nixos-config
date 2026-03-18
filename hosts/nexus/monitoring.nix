# Nexus Monitoring Configuration
# Storage/GPU node
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # SERVICES CONFIGURATION
  services = {
    # System monitoring CLI tools
    monitoring.system-tools = {
      enable = true;
      packageSet = "standard";
    };

    # Node exporter for Prometheus scraping (from Sentry)
    monitoring.node-exporter = {
      enable = true;
      listenAddress = "0.0.0.0"; # Allow cluster scraping
    };

    # SMART exporter for disk health monitoring
    monitoring.smart-exporter.enable = true;

    # Mining exporter for CPU/GPU mining metrics
    mining-exporter.enable = true;

    # Log aggregation to Sentry's Loki
    monitoring.promtail = {
      enable = true;
      lokiUrl = "http://10.1.1.140:3100/loki/api/v1/push";
    };
  };
}
