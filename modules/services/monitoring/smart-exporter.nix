# SMART Exporter for Prometheus
# Collects S.M.A.R.T. metrics from disk drives for health monitoring
# Uses smartctl with node_exporter textfile collector
{
  config,
  lib,
  pkgs,
  ...
}: let
    cfg = config.services.monitoring.smart-exporter;
    metricsDir = "/var/lib/prometheus/node-exporter/textfile-collector";
    outputFile = "${metricsDir}/smart.prom";
in {
  options.services.monitoring.smart-exporter = {
    enable = lib.mkEnableOption "S.M.A.R.T. metrics exporter for Prometheus";

    devices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of devices to monitor (e.g., [\"/dev/nvme0n1\" \"/dev/sda\"]). Empty = auto-detect all.";
    };

    collectPeriod = lib.mkOption {
      type = lib.types.int;
      default = 300;
      description = "Collection interval in seconds";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure smartmontools is installed
    environment.systemPackages = with pkgs; [smartmontools];

    # Create the collector script
    systemd.services.smart-metrics-exporter = {
      description = "SMART Metrics Exporter";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "prometheus-node-exporter.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "smart-metrics-collector" ''
          #!/bin/sh
          set -euo pipefail

          METRICS_FILE="${outputFile}"

          # Help header
          echo "# HELP smart_device_smart_healthy SMART overall health self-test status (1=passed, 0=failed)" > "$METRICS_FILE"
          echo "# TYPE smart_device_smart_healthy gauge" >> "$METRICS_FILE"
          echo "# HELP smart_device_remaining_percent Percentage of remaining life (attribute 233)" >> "$METRICS_FILE"
          echo "# TYPE smart_device_remaining_percent gauge" >> "$METRICS_FILE"
          echo "# HELP smart_device_temperature_celsius Drive temperature in Celsius" >> "$METRICS_FILE"
          echo "# TYPE smart_device_temperature_celsius gauge" >> "$METRICS_FILE"

          # Devices to scan
          ${if cfg.devices == [] then ''# Auto-detect all devices
            DEVICES=$(smartctl --scan-open | grep -oE '/dev/(nvme[0-9]+|sd[a-z]+)' || true)
          else
            DEVICES="${lib.concatStringsSep " " cfg.devices}"
          fi''}

          for device in $DEVICES; do
            [ -e "$device" ] || continue

            # Get device name for labels
            devname=$(basename "$device")

            # Overall health
            health=$(smartctl -H "$device" 2>/dev/null | grep -oP 'SMART overall-health self-assessment test result: \K.*' || echo "unknown")
            if [ "$health" = "PASSED" ] || [ "$health" = "OK" ]; then
              echo "smart_device_smart_healthy{device=\"$devname\"} 1" >> "$METRICS_FILE"
            else
              echo "smart_device_smart_healthy{device=\"$devname\"} 0" >> "$METRICS_FILE"
            fi

            # Remaining life percentage (SSD)
            remaining=$(smartctl -A "$device" 2>/dev/null | grep -oP '233 \K\d+' || echo "")
            if [ -n "$remaining" ]; then
              echo "smart_device_remaining_percent{device=\"$devname\"} $remaining" >> "$METRICS_FILE"
            fi

            # Temperature
            temp=$(smartctl -A "$device" 2>/dev/null | grep -oP '194 Temperature_Celsius.*? \K\d+' || echo "")
            if [ -n "$temp" ]; then
              echo "smart_device_temperature_celsius{device=\"$devname\"} $temp" >> "$METRICS_FILE"
            fi

            # Timestamp
            echo "smart_scrape_timestamp $(date +%s)" >> "$METRICS_FILE"
          done
        '';
        Restart = "on-failure";
        RestartSec = "${toString cfg.collectPeriod}s";
      };
    };

    # Run every N seconds via timer
    systemd.timers.smart-metrics-exporter = {
      description = "SMART Metrics Exporter Timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "${toString cfg.collectPeriod}s";
      };
    };
  };
}
