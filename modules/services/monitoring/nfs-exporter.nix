# NFS Server Metrics Exporter
# Collects NFS server stats from /proc/fs/nfsd for Prometheus
# Should be enabled on zephyr (the NFS server for /etc/nixos)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.monitoring.nfs-exporter;
  metricsDir = "/var/lib/prometheus/node-exporter/textfile-collector";
  outputFile = "${metricsDir}/nfsd.prom";
in {
  options.services.monitoring.nfs-exporter = {
    enable = lib.mkEnableOption "NFS server metrics exporter";

    interval = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Scrape interval in seconds";
    };
  };

  config = lib.mkIf cfg.enable {
    # Systemd service to run the collector periodically
    systemd.services.nfs-metrics-exporter = {
      description = "NFS Server Metrics Exporter";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target" "prometheus-node-exporter.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "nfs-metrics-collector" ''
          #!/bin/sh
          set -euo pipefail

          METRICS_FILE="${outputFile}"
          PROC_DIR="/proc/fs/nfsd"

          # Check if NFS server is running
          if [ ! -d "$PROC_DIR" ]; then
            echo "# NFS server not running" > "$METRICS_FILE"
            exit 0
          fi

          echo "# HELP nfsd_stats_total NFS server operations total" > "$METRICS_FILE"
          echo "# TYPE nfsd_stats_total counter" >> "$METRICS_FILE"

          # Read stats from /proc/fs/nfsd/stats
          if [ -f "$PROC_DIR/stats" ]; then
            # Parse the stats file and append to metrics
            {
              while IFS= read -r line; do
                case "$line" in
                  rc*)
                    # Reply cache stats: rc hits misses nocache
                    set -- $line
                    hits=$2
                    misses=$3
                    nocache=$4
                    echo "nfsd_rc_hits_total $hits"
                    echo "nfsd_rc_misses_total $misses"
                    echo "nfsd_rc_nocache_total $nocache"
                    ;;
                  read*)
                    # Read stats
                    set -- $line
                    ok=$2
                    echo "nfsd_read_total $ok"
                    ;;
                  write*)
                    # Write stats
                    set -- $line
                    ok=$2
                    echo "nfsd_write_total $ok"
                    ;;
                esac
              done < "$PROC_DIR/stats"
            } >> "$METRICS_FILE"
          fi

          # Get NFS export info
          echo "# HELP nfsd_exports_total Number of NFS exports" >> "$METRICS_FILE"
          echo "# TYPE nfsd_exports_total gauge" >> "$METRICS_FILE"

          # grep -c returns exit 1 when no matches, use || true to handle
          export_count=$(showmount -e 127.0.0.1 2>/dev/null | grep -c "^/" || echo "0" || true)
          echo "nfsd_exports_total $export_count" >> "$METRICS_FILE"
        '';
        Restart = "on-failure";
        RestartSec = "${toString cfg.interval}s";
      };
    };

    # Run every N seconds via timer
    systemd.timers.nfs-metrics-exporter = {
      description = "NFS Server Metrics Exporter Timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10s";
        OnUnitActiveSec = "${toString cfg.interval}s";
      };
    };
  };
}
