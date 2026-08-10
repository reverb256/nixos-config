# Sentry Monitoring Configuration
{lib, ...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # SERVICES CONFIGURATION
  services = {
    # System monitoring CLI tools
    monitoring.system-tools = {
      enable = true;
      packageSet = "standard"; # htop, iotop, nethogs, iftop, perf
    };

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

      # Sentry runs Loki single-node (inmemory kvstore, replication_factor=1).
      # The default memberlist bind scans interfaces [eth0 en0 lo] and fails on
      # the (nonexistent) en0 interface. Pin memberlist to loopback so the
      # gossip layer binds without interface autodiscovery. HTTP ingest still
      # listens on 0.0.0.0:3100 for cluster-wide push.
      loki.extraConfiguration = {
        memberlist = {
          bind_addr = "127.0.0.1";
          bind_port = 7946;
        };
      };

      # Metrics exporters
      node-exporter.enable = true;
      smart-exporter.enable = true;

      # Log aggregation (local Loki)
      # promtail removed from nixpkgs (EOL). Migrate to fluent-bit.
      # promtail.enable = true;
      # promtail.lokiUrl = "http://127.0.0.1:3100/loki/api/v1/push";
    };

    # Note: Sentry has no GPUs, no GPU exporters needed

    # Sentry has no local mining workload or mining exporter.

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
      enableCircuitBreakerAlerts = false; # No AI gateway on Sentry
      enableVIPFailoverAlerts = true;
      enableResourceAlerts = true;
      memoryThreshold = 90;
      diskThreshold = 90;
    };
    # Log shipping to Loki (Grafana Alloy)
    monitoring.grafana-alloy.enable = true;
    monitoring.ntfy.enable = true;
  };

  # Ensure node-exporter port is open for Prometheus scraping
  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [9100];
}
