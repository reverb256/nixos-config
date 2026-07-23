# Zephyr Monitoring Configuration
# Control plane node - minimal monitoring footprint
{ ... }:
{
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

    # Log aggregation to Sentry's Loki
    gputemps-exporter.enable = true;

    monitoring.smart-exporter.enable = true;

    monitoring.promtail = {
      enable = false;
      lokiUrl = "http://10.1.1.140:3100/loki/api/v1/push";
    };
    # Log shipping to Loki (Grafana Alloy)
    monitoring.grafana-alloy.enable = true;
  };

  # Ensure node-exporter port is open for Prometheus scraping
  networking.firewall.allowedTCPPorts = [ 9100 ];
}
