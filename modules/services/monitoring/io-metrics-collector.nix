{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.monitoring.io-metrics-collector;
  inherit (lib) mkEnableOption mkIf mkOption types;
  textfileDir = "/var/lib/prometheus/node-exporter/textfile-collector";
in {
  options.services.monitoring.io-metrics-collector = {
    enable = mkEnableOption "I/O metrics collector for node_exporter textfile";

    interval = mkOption {
      type = types.int;
      default = 60;
      description = "Collection interval in seconds (disk, zram, NFS)";
    };

    btrfsInterval = mkOption {
      type = types.str;
      default = "weekly";
      description = "BTRFS stats collection interval (weekly or monthly)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.btrfs-progs];

    systemd.services.io-metrics-collector = {
      description = "Collect disk, zram, and NFS I/O metrics";
      wantedBy = ["multi-user.target"];
      after = ["prometheus-node-exporter.service"];
      path = [pkgs.coreutils pkgs.bash pkgs.btrfs-progs];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "io-metrics-collector" ''
          set -euo pipefail

          METRICS_FILE="${textfileDir}/io-metrics.prom.$$"
          cleanup() { rm -f "$METRICS_FILE"; }
          trap cleanup EXIT

          echo "# HELP node_disk_latency_ms Average I/O service time in milliseconds per disk" >> "$METRICS_FILE"
          echo "# TYPE node_disk_latency_ms gauge" >> "$METRICS_FILE"

          for dev in /sys/block/nvme*; do
            devname=''${dev##*/}
            stat_file="$dev/stat"
            if [ -r "$stat_file" ]; then
              # Parse disk stat: reads, reads_merged, reads_sectors, reads_ms, writes...
              read -r _ _ _ reads_ms _ _ _ _ writes_ms _ _ _ _ _ _ _ _ _ _ _ _ < "$stat_file"
              if [ -n "$reads_ms" ] && [ -n "$writes_ms" ]; then
                total_ops=$(awk "/$devname/{print \$4+\$8}" /proc/diskstats 2>/dev/null || echo 1)
                if [ "$total_ops" -gt 0 ]; then
                  avg_latency=$(awk "BEGIN {printf \"%.2f\", ($reads_ms + $writes_ms) / $total_ops}")
                  echo "node_disk_latency_ms{device=\"$devname\"} $avg_latency" >> "$METRICS_FILE"
                fi
              fi
            fi
          done

          echo "# HELP node_zram_orig_data_size_bytes Uncompressed size of data in zram" >> "$METRICS_FILE"
          echo "# TYPE node_zram_orig_data_size_bytes gauge" >> "$METRICS_FILE"
          echo "# HELP node_zram_compr_data_size_bytes Compressed size of data in zram" >> "$METRICS_FILE"
          echo "# TYPE node_zram_compr_data_size_bytes gauge" >> "$METRICS_FILE"
          echo "# HELP node_zram_mem_used_total_bytes Memory used by zram" >> "$METRICS_FILE"
          echo "# TYPE node_zram_mem_used_total_bytes gauge" >> "$METRICS_FILE"

          if [ -r "/sys/block/zram0/mm_stat" ]; then
            read -r orig_data_size compr_data_size _ mem_used_total _ < /sys/block/zram0/mm_stat
            echo "node_zram_orig_data_size_bytes $orig_data_size" >> "$METRICS_FILE"
            echo "node_zram_compr_data_size_bytes $compr_data_size" >> "$METRICS_FILE"
            echo "node_zram_mem_used_total_bytes $mem_used_total" >> "$METRICS_FILE"
          fi

          echo "# HELP node_nfsd_rpc_calls_total Total NFS RPC calls" >> "$METRICS_FILE"
          echo "# TYPE node_nfsd_rpc_calls_total counter" >> "$METRICS_FILE"
          echo "# HELP node_nfsd_read_bytes_total Total NFS bytes read" >> "$METRICS_FILE"
          echo "# TYPE node_nfsd_read_bytes_total counter" >> "$METRICS_FILE"
          echo "# HELP node_nfsd_write_bytes_total Total NFS bytes written" >> "$METRICS_FILE"
          echo "# TYPE node_nfsd_write_bytes_total counter" >> "$METRICS_FILE"

          if [ -r "/proc/net/rpc/nfsd" ]; then
            while IFS= read -r line; do
              case $line in
                "proc3"*)
                  read -r _ _ _ reads _ _ _ writes _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ <<< "$line"
                  echo "node_nfsd_rpc_calls_total $((reads + writes))" >> "$METRICS_FILE"
                  ;;
                "io"*)
                  read -r _ _ _ read_bytes _ _ _ write_bytes _ _ _ <<< "$line"
                  echo "node_nfsd_read_bytes_total $read_bytes" >> "$METRICS_FILE"
                  echo "node_nfsd_write_bytes_total $write_bytes" >> "$METRICS_FILE"
                  ;;
              esac
            done < /proc/net/rpc/nfsd
          fi

          mv "$METRICS_FILE" "${textfileDir}/io-metrics.prom"
        '';

        nice = 15;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.io-metrics-collector = {
      description = "Timer for I/O metrics collector";
      wantedBy = ["timers.target"];
      timerConfig.OnCalendar = "*:0/1";
      timerConfig.Persistent = true;
    };

    systemd.services.io-metrics-btrfs = {
      description = "Collect BTRFS device stats";
      wantedBy = ["multi-user.target"];
      after = ["prometheus-node-exporter.service"];
      path = [pkgs.coreutils pkgs.bash pkgs.btrfs-progs];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "io-metrics-btrfs" ''
          set -euo pipefail

          METRICS_FILE="${textfileDir}/io-btrfs.prom.$$"
          cleanup() { rm -f "$METRICS_FILE"; }
          trap cleanup EXIT

          echo "# HELP node_btrfs_checksum_errors_total BTRFS checksum error count" >> "$METRICS_FILE"
          echo "# TYPE node_btrfs_checksum_errors_total gauge" >> "$METRICS_FILE"
          echo "# HELP node_btrfs_io_errors_total BTRFS I/O error count" >> "$METRICS_FILE"
          echo "# TYPE node_btrfs_io_errors_total gauge" >> "$METRICS_FILE"
          echo "# HELP node_btrfs_flush_errors_total BTRFS flush error count" >> "$METRICS_FILE"
          echo "# TYPE node_btrfs_flush_errors_total gauge" >> "$METRICS_FILE"

          for mount in $(findmnt -t btrfs -n -o TARGET --target / /home /data 2>/dev/null); do
            if [ -n "$mount" ]; then
              btrfs device stats "$mount" 2>/dev/null | while IFS=: read -r key value; do
                key=$(echo "$key" | tr -d ' ')
                value=$(echo "$value" | tr -d ' ')
                case $key in
                  "checksum_errors")
                    echo "node_btrfs_checksum_errors_total{mount=\"$mount\"} $value" >> "$METRICS_FILE"
                    ;;
                  "read_io_errors")
                    echo "node_btrfs_io_errors_total{mount=\"$mount\",type=\"read\"} $value" >> "$METRICS_FILE"
                    ;;
                  "write_io_errors")
                    echo "node_btrfs_io_errors_total{mount=\"$mount\",type=\"write\"} $value" >> "$METRICS_FILE"
                    ;;
                  "flush_io_errors")
                    echo "node_btrfs_flush_errors_total{mount=\"$mount\"} $value" >> "$METRICS_FILE"
                    ;;
                esac
              done || true
            fi
          done

          mv "$METRICS_FILE" "${textfileDir}/io-btrfs.prom"
        '';

        nice = 15;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.io-metrics-btrfs = {
      description = "Timer for BTRFS stats collector";
      wantedBy = ["timers.target"];
      timerConfig.OnCalendar = if cfg.btrfsInterval == "weekly" then "Mon 03:00" else "monthly";
      timerConfig.Persistent = true;
    };
  };
}