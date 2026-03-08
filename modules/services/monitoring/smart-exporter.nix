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

    # Script to collect SMART metrics
    environment.etc."smart-metrics-collector.sh".text = ''
      #!/bin/sh
      # Collect S.M.A.R.T. metrics for Prometheus node_exporter textfile collector

      METRICS_FILE="${outputFile}"
      SMARTCTL="${pkgs.smartmontools}/bin/smartctl"

      # Help header
      echo "# HELP smart_device_smart_healthy SMART overall health self-test status (1=passed, 0=failed)" > "$METRICS_FILE"
      echo "# TYPE smart_device_smart_healthy gauge" >> "$METRICS_FILE"
      echo "# HELP smart_device_remaining_percent Percentage of remaining life (attribute 233)" >> "$METRICS_FILE"
      echo "# TYPE smart_device_remaining_percent gauge" >> "$METRICS_FILE"
      echo "# HELP smart_device_temperature_celsius Drive temperature in Celsius" >> "$METRICS_FILE"
      echo "# TYPE smart_device_temperature_celsius gauge" >> "$METRICS_FILE"

      # Devices to scan
      if [ ${builtins.length cfg.devices} -gt 0 ]; then
        DEVICES="${lib.concatStringsSep " " cfg.devices}"
      else
        # Auto-detect all devices
        DEVICES="$($SMARTCTL --scan-open | grep -oE '/dev/(nvme[0-9]+|sd[a-z]+)')"
      fi

      for device in $DEVICES; do
        [ -e "$device" ] || continue

        # Get device name for labels
        devname=$(basename "$device")

        # Overall health (SMART overall-health self-assessment test result)
        health=$($SMARTCTL -H "$device" | grep -oP 'SMART overall-health self-assessment test result: \K.*' || echo "unknown")
        if [ "$health" = "PASSED" ] || [ "$health" = "OK" ]; then
          echo "smart_device_smart_healthy{device=\"$devname\"} 1" >> "$METRICS_FILE"
        else
          echo "smart_device_smart_healthy{device=\"$devname\"} 0" >> "$METRICS_FILE"
        fi

        # Remaining life percentage (SSD) or spin-up time (HDD)
        # Attribute 233 for SSDs, 9 for HDDs
        remaining=$($SMARTCTL -A "$device" | grep -oP '233 \K\d+' || $SMARTCTL -A "$device" | grep -oP '9 \K\d+')
        if [ -n "$remaining" ]; then
          echo "smart_device_remaining_percent{device=\"$devname\"} $remaining" >> "$METRICS_FILE"
        fi

        # Temperature
        temp=$($SMARTCTL -A "$device" | grep -oP '194 Temperature_Celsius \K\d+' || $SMARTCTL -A "$device" | grep -oP 'Temperature:' | grep -oP '\d+')
        if [ -n "$temp" ]; then
          echo "smart_device_temperature_celsius{device=\"$devname\"} $temp" >> "$METRICS_FILE"
        fi

        # Error count (attributes 5, 10, 187, 188)
        errors=$($SMARTCTL -A "$device" | grep -E ' (5|10|187|188) ' | grep -oP '\d+\s*$' | awk '{sum+=$1} END {print sum}')
        if [ -n "$errors" ] && [ "$errors" -gt 0 ]; then
          echo "smart_device_errors_total{device=\"$devname\"} $errors" >> "$METRICS_FILE"
        fi

        # Power cycle count
        power_cycles=$($SMARTCTL -A "$device" | grep -oP '12 Power_Cycle_Count \K\d+' || echo "0")
        echo "smart_device_power_cycles_total{device=\"$devname\"} $power_cycles" >> "$METRICS_FILE"

        # Power on hours
        power_hours=$($SMARTCTL -A "$device" | grep -oP '9 Power_On_Hours \K\d+' || echo "0")
        echo "smart_device_power_on_hours{device=\"$devname\"} $power_hours" >> "$METRICS_FILE"
      done

      # Timestamp
      echo "smart_scrape_timestamp $(date +%s)" >> "$METRICS_FILE"
    '';

    # Systemd service to run the collector periodically
    systemd.services.smart-metrics-exporter = {
      description = "SMART Metrics Exporter";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "prometheus-node-exporter.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/nixos/smart-metrics-collector.sh";
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
