{ ... }:
{
  imports = [
    ./prometheus.nix
    ./alertmanager.nix
    ./alert-webhook.nix
    ./grafana-v2.nix
    ./alert-rules.nix
    ./node-exporter.nix
    ./nfs-exporter.nix
    ./redis-exporter.nix
    ./smart-exporter.nix
    ./loki.nix
    ./system-tools.nix
    ./xmrig-metrics.nix
  ];
}
