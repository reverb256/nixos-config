# Monitoring Infrastructure Modules
# Prometheus, Grafana, and exporters for cluster observability
{...}: {
  imports = [
    ./prometheus.nix
    ./grafana.nix
    ./node-exporter.nix
  ];
}
