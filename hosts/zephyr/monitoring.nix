# Zephyr Monitoring Configuration
{...}: {
  imports = [
    ../../modules/services/monitoring/default.nix
  ];

  # SERVICES CONFIGURATION
  services = {
    # Monitoring stack
    monitoring = {
      # Prometheus for local metrics and alerting
      prometheus.enable = true;

      # AlertManager for local alert routing
      alertmanager.enable = true;

      # Local webhook receiver for desktop notifications (no password required)
      alert-webhook.enable = true;

      # Node exporter for system metrics (CPU, memory, disk, network)
      node-exporter.enable = true;

      # NFS server metrics exporter (zephyr exports /etc/nixos to cluster)
      nfs-exporter.enable = true;

      # Redis exporter for AI Gateway cache metrics
      redis-exporter.enable = true;

      # SMART exporter for disk health monitoring
      smart-exporter.enable = true;
    };

    # GPU metrics exporter (NVIDIA RTX 3090 + 3060 Ti)
    gpu-exporters.enable = true;
    gpu-exporters.nvidia.enable = true;

    # Mining exporter (for mining operations on zephyr)
    # Track hashrate, power usage, shares accepted/rejected
    mining-exporter.enable = true;
  };
}
