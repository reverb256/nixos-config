# Prometheus Node Exporter
# System metrics exporter for Prometheus
# Should be enabled on all cluster hosts
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.monitoring.node-exporter;
in
{
  options.services.monitoring.node-exporter = {
    enable = lib.mkEnableOption "Prometheus node exporter";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Port for node exporter";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to listen on";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.node = {
      enable = true;
      port = cfg.port;
      listenAddress = cfg.listenAddress;

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
      ];

      # Textfile collector directory for custom metrics
      extraFlags = [
        "--collector.textfile.directory=/var/lib/prometheus/node-exporter/textfile-collector"
      ];
    };

    # Fix race condition: wait for network to be fully online before starting
    systemd.services.prometheus-node-exporter = {
      after = ["network-online.target"];
      wants = ["network-online.target"];
    };

    # Open firewall for Prometheus to scrape metrics
    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}
