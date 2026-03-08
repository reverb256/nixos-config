# Prometheus Node Exporter
# System metrics exporter for Prometheus
# Should be enabled on all cluster hosts
{
  config,
  lib,
  ...
}: let
  cfg = config.services.monitoring.node-exporter;
  # Use centralized network constants
  port = config.networking.cluster.ports.node-exporter;
  currentHost =
    config.networking.cluster.hosts.${
      config.networking.hostName
    } or {
      ip = "0.0.0.0";
    };
in {
  options.services.monitoring.node-exporter = {
    enable = lib.mkEnableOption "Prometheus node exporter";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = currentHost.ip;
      description = "Address to listen on (defaults to host's cluster IP)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.node = {
      enable = true;
      inherit port;
      inherit (cfg) listenAddress;

      # Collectors enabled
      enabledCollectors = [
        "cpu"
        "diskstats"
        "filesystem"
        "loadavg"
        "meminfo"
        "netdev"
        "stat"
        "time"
        "uname"
        "hwmon"
        "netclass"
        "buddyinfo"
        "ksmd"
        "logind"
        "pressure"
        "processes"
        "systemd"
        "tcpstat"
        "vmstat"
        "zfs"
        "textfile"
        "nfs"  # NFS client metrics
      ];

      # Textfile collector directory for custom metrics (e.g., AMD GPU)
      extraFlags = [
        "--collector.textfile.directory=/var/lib/prometheus/node-exporter/textfile-collector"
      ];
    };

    # Fix race condition: wait for network to be fully online before starting
    # This ensures static IPs are assigned before node-exporter tries to bind
    systemd.services.prometheus-node-exporter = {
      after = ["network-online.target"];
      wants = ["network-online.target"];
    };

    # Open firewall for Prometheus to scrape metrics
    networking.firewall.allowedTCPPorts = [
      port
    ];
  };
}
