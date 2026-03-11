# Sentry Monitoring Configuration
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # SERVICES CONFIGURATION
  services = {
    # Monitoring stack
    monitoring = {
      # Core monitoring services
      prometheus.enable = true;
      grafana.enable = true;
      alertmanager.enable = true;
      # Local webhook notifications (no password required)
      alert-webhook.enable = true;
      # Email disabled (requires SMTP password)
      alertmanager.email.enable = false;
      loki.enable = true;

      # Metrics exporters
      node-exporter.enable = true;
      smart-exporter.enable = true;

      # Log aggregation
      promtail.enable = true;
      promtail.lokiUrl = "http://100.81.182.5:3100"; # Zephyr's Tailscale IP
    };

    # Note: Sentry has no GPUs, no GPU exporters needed

    # Mining exporter for CPU mining metrics
    mining-exporter.enable = true;
  };
}
