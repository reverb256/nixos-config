# Monitoring Infrastructure Modules
# Prometheus, Grafana, and exporters for cluster observability
{ ... }:
{
  imports = [
    ./prometheus.nix
    ./alertmanager.nix
    ./alert-webhook.nix # Local webhook receiver (no auth required)
    ./grafana-v2.nix # New modular dashboard system
    ./node-exporter.nix
    ./nfs-exporter.nix
    ./redis-exporter.nix
    ./smart-exporter.nix
    ./loki.nix
    ./alert-rules.nix  # Cluster alert rules (disk, temp, GPU, service health)
    ./ntfy.nix           # Phone push notifications via ntfy
    ./dcgm-exporter.nix  # NVIDIA DCGM hardware error tracking (ECC, PCIe)
    ./grafana-alloy.nix  # Log shipper to Loki (replaces promtail)
    ./promtail.nix # Log aggregation to Loki
    ./system-tools.nix # CLI monitoring tools (htop, iotop, nethogs, sysstat)
  ];
}
