{
  config,
  lib,
  ...
}: let
  cfg = config.services.monitoring.node-exporter;
  port = 9100; # Default node-exporter port (networking.cluster.ports.node-exporter)
in {
  options.services.monitoring.node-exporter = {
    enable = lib.mkEnableOption "Prometheus node exporter";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to listen on (use 127.0.0.1 for localhost-only)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.node = {
      enable = true;
      inherit port;
      inherit (cfg) listenAddress;

      enabledCollectors = [
        "cpu"
        "diskstats"
        "loadavg"
        "meminfo"
        "netdev"
        "pressure"
        "time"
        "uname"
        "netclass"
        "tcpstat"
        "vmstat"
      ];

      extraFlags = [
        "--collector.textfile.directory=/var/lib/prometheus/node-exporter/textfile-collector"
      ];
    };

    systemd.services.prometheus-node-exporter = {
      after = ["network-online.target"];
      wants = ["network-online.target"];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/prometheus/node-exporter/textfile-collector 0755 root root -"
    ];

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      port
    ];
  };
}
