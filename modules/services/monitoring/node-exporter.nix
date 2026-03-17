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
in {
  options.services.monitoring.node-exporter = {
    enable = lib.mkEnableOption "Prometheus node exporter";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0"; # For cluster Prometheus scraping (protected by firewall - only internal network)
      description = "Address to listen on (use 127.0.0.1 for localhost-only)";
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
        # "filesystem"  # Disabled - can hang on NFS mounts (NixOS shared /etc/nixos)
        "loadavg"
        "meminfo"
        "netdev"
        # "stat"  # Disabled - can hang on some systems
        "time"
        "uname"
        # "hwmon"  # Disabled - can hang on some systems
        "netclass"
        # "buddyinfo"  # Disabled - can cause hangs on some systems
        # "ksmd"  # Disabled - can cause hangs on some systems
        # "logind"  # Disabled - can hang on some systems
        # "pressure"  # Disabled - can cause hangs on some systems
        # "processes"  # Disabled - can hang on some systems
        # "systemd"  # Disabled - can hang on some systems
        "tcpstat"
        "vmstat"
        # "zfs"  # Disabled - no ZFS pools in cluster
        # "textfile"  # Disabled - configured via extraFlags to avoid duplicate flag
        # "nfs"  # Disabled - causes metrics endpoint to hang on hosts with NFS mounts
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
