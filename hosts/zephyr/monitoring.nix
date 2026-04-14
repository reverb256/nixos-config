# Zephyr Monitoring Configuration
# Control plane node - minimal monitoring footprint
{ lib, ... }:
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

    # Log aggregation - DISABLED (promtail EOL, needs migration to grafana-alloy)
    #     monitoring.promtail = {
    #       enable = false;
    #       lokiUrl = "http://10.1.1.140:3100/loki/api/v1/push";
    #     };

    # XMRig CPU miner metrics -> node-exporter textfile collector
    xmrig-metrics = {
      enable = true;
      targets = [
        "127.0.0.1:8082"
        "127.0.0.1:8083"
      ];
      interval = 30;
    };
  };

  # Ensure node-exporter port is open for Prometheus scraping
  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ 9100 ];
}
