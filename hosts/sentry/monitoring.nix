# Sentry Monitoring Configuration
{lib, ...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # SERVICES CONFIGURATION
  services = {
    # Read-only fleet RGB inventory. Stylix sync remains disabled until
    # stable device identities are explicitly approved in the contract.
    rgb-inventory.enable = true;
    # System monitoring CLI tools
    monitoring.system-tools = {
      enable = true;
      packageSet = "standard"; # htop, iotop, nethogs, iftop, perf
    };

    # Monitoring stack
    monitoring = {
      # Core monitoring services
      prometheus.enable = true;
      # Cluster alert rules (host, GPU, service, temperature)
      prometheus.enableAlertRules = true;
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
      # Loki 3.7.4 memberlist fails with "no useable address found for
      # interfaces [eth0 en0 lo]" because en0 does not exist on Linux.
      # Single-node Loki binds memberlist to 0.0.0.0; HTTP ingest listens on
      # cfg.listenAddress (0.0.0.0:3100) for cluster-wide push.
      loki.extraConfiguration = {
        memberlist = {
          # memberlist.bind_addr is a StringSlice -> must be a list, not a
          # bare string.  Bind to 0.0.0.0: single-node Loki with inmemory
          # kvstore doesn't gossip across hosts, and binding to 127.0.0.1
          # makes Loki 3.7.4 fail with "no useable address found for
          # interfaces [eth0 en0 lo]" (en0 does not exist on Linux).
          bind_addr = ["0.0.0.0"];
          bind_port = 7946;
        };
        # Single-tenant homelab: without this, Loki 3.x requires an
        # X-Scope-OrgID header on every push and alloy's loki.write gets
        # "no org id" 401s (observed 2026-08-16 after the sentry reboot).
        # auth_enabled=false maps everything to the implicit "fake" tenant.
        auth_enabled = false;
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
    # ntfy disabled: the pinned nixpkgs rev ships a broken ntfy package
    # (binary's runtime check rejects the schema its own init writes:
    # 'unexpected schema version: version 9 is higher than current version 8').
    # It fails to start, which makes sentry activation fail (code 4) and
    # stalls the whole colmena apply. Disable until the ntfy package is
    # fixed/overridden. Alerting via grafana-alloy + Alertmanager remains.
    monitoring.ntfy.enable = false;
  };

  # Ensure node-exporter port is open for Prometheus scraping
  networking.firewall.allowedTCPPorts = lib.mkOptionDefault [9100];
}
