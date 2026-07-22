# Forge Monitoring Configuration
# GPU computing node
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

    # NOTE (2026-07-21, issue #300): mining-exporter and gputemps-exporter
    # modules were removed with the lolminer/xmrig purge. Forge mining now
    # flows through the peakminer K8s deployment — see
    # hosts/forge/peakminer.nix and kubernetes/modules/profit-switcher.nix
    # — which exposes its own Prometheus metrics. No replace exporter needed.

    # Log aggregation to Sentry's Loki.
    # NOTE: promtail was removed from nixpkgs 26.05 (EOL). Disabled here to
    # unblock eval; migrate to grafana-alloy or fluent-bit when log shipping
    # is needed again. See tracking item.
    monitoring.promtail = {
      enable = false;
      lokiUrl = "http://10.1.1.140:3100/loki/api/v1/push";
    };
  };
}
