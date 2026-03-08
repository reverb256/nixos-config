# Monitoring Infrastructure Modules
# Prometheus, Grafana, and exporters for cluster observability
{...}: {
  imports = [
    ./prometheus.nix
    ./alertmanager.nix
    ./grafana-v2.nix  # New modular dashboard system
    ./node-exporter.nix
    ./nfs-exporter.nix
    ./redis-exporter.nix
    ./smart-exporter.nix
    ./loki.nix
  ];
}
