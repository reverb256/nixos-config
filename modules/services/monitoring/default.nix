# Monitoring Infrastructure Modules
# Prometheus, Grafana, and exporters for cluster observability
{...}: {
  imports = [
    ./prometheus.nix
    ./grafana.nix
    ./node-exporter.nix
    ./nfs-exporter.nix
    ./redis-exporter.nix
    ./smart-exporter.nix
    ../gpu-exporters.nix
    ../mining-exporter.nix
    ../auto-secrets.nix
    ../claude-auto-update.nix
  ];
}
