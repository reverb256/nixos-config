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
      loki = {
        enable = true;
        listenAddress = "0.0.0.0"; # Allow cluster-wide access
        dataDir = "/storage/loki"; # Use persistent storage
      };

      # Metrics exporters
      node-exporter.enable = true;
      smart-exporter.enable = true;

      # Log aggregation (local Loki)
      promtail.enable = true;
      promtail.lokiUrl = "http://127.0.0.1:3100/loki/api/v1/push";
    };

    # Note: Sentry has no GPUs, no GPU exporters needed

    # Mining exporter for CPU mining metrics
    mining-exporter.enable = true;

    # Self-healing alerts via Plasma desktop notifications
    self-healing-alerts = {
      enable = true;
      monitoredServices = [
        "kubelet"
        "kube-apiserver"
        "containerd"
        "etcd"
        "keepalived"
      ];
      enableCircuitBreakerAlerts = false;  # No AI gateway on Sentry
      enableVIPFailoverAlerts = true;
      enableResourceAlerts = true;
      memoryThreshold = 90;
      diskThreshold = 90;
    };
  };
}
