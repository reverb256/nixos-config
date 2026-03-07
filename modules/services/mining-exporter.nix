# Mining Metrics Exporter for Prometheus
# Exports lolminer and xmrig metrics for cluster monitoring
#
# Polls mining APIs and exposes metrics for:
# - Hashrate (per GPU and total)
# - Power consumption
# - Temperature
# - Shares (accepted/rejected)
# - Uptime
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.mining-exporter;

  # Python HTTP server script for serving metrics with correct Content-Type
  httpServerScript = pkgs.writeText "mining-exporter-http-server.py" ''
    import http.server
    import socketserver
    import sys
    import os

    PORT = int(sys.argv[1])
    METRICS_FILE = sys.argv[2]

    class MetricsHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/metrics':
                self.send_response(200)
                # Prometheus requires text/plain Content-Type
                self.send_header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
                self.end_headers()
                if os.path.exists(METRICS_FILE):
                    with open(METRICS_FILE, 'r') as f:
                        self.wfile.write(f.read().encode('utf-8'))
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, format, *args):
            # Suppress access logs to reduce journal spam
            pass

    # Allow port reuse to avoid "Address already in use" on rapid restarts
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), MetricsHandler) as httpd:
        httpd.serve_forever()
  '';

  # Mining configuration per host
  hosts = {
    zephyr = {
      nvidia = true;
      amd = false;
      cpu = true;
      lolminerPort = 4068;
      xmrigPort = 8081;
    };
    nexus = {
      nvidia = true;
      amd = false;
      cpu = true;
      lolminerPort = 4068;
      xmrigPort = 8081;
    };
    forge = {
      nvidia = true;
      amd = true;
      cpu = false;
      lolminerPort = 4068;
      lolminerAmdPort = 4069;
      xmrigPort = 8081;
    };
    sentry = {
      nvidia = false;
      amd = false;
      cpu = true;
      xmrigPort = 8081;
    };
  };

  currentHost = config.networking.hostName;
  hostConfig = hosts.${currentHost} or null;
in {
  options.services.mining-exporter = {
    enable = lib.mkEnableOption "Mining metrics exporter for Prometheus";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9105;
      description = "Port for mining metrics exporter";
    };

    scrapeInterval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = "How often to poll mining APIs";
    };
  };

  config = lib.mkIf (cfg.enable && hostConfig != null) {
    # Create prometheus user/group (for hosts without prometheus server)
    users.users.prometheus = lib.mkIf (!config.services.prometheus.enable) {
      isSystemUser = true;
      group = "prometheus";
    };
    users.groups.prometheus = lib.mkIf (!config.services.prometheus.enable) {};

    # Mining exporter systemd service
    systemd.services.prometheus-mining-exporter = {
      description = "Prometheus Mining Metrics Exporter";
      wantedBy = ["multi-user.target"];
      after = [
        "network.target"
        "lolminer.service"
        "xmrig.service"
      ];

      serviceConfig = {
        Type = "simple";
        User = "prometheus";
        Group = "prometheus";
        RuntimeDirectory = "prometheus/mining-exporter";
        ExecStart = pkgs.writers.writeBash "mining-exporter" ''
          set -euo pipefail

          PORT=${toString cfg.port}
          HOSTNAME="$(${pkgs.hostname}/bin/hostname)"
          INTERVAL_SECONDS=15

          METRICS_DIR="/run/prometheus/mining-exporter"
          cd "$METRICS_DIR"

          # Helper to escape labels
          escape_label() {
            ${pkgs.gnused}/bin/sed 's/"/\\"/g; s/[^a-zA-Z0-9:_]/_/g'
          }

          HOST_LABEL="\"$(echo "$HOSTNAME" | escape_label)\""

          # Temporary file for accumulating metrics
          METRICS_FILE="$METRICS_DIR/metrics.tmp"

          # Fetch lolminer metrics (appends to METRICS_FILE)
          fetch_lolminer() {
            local port=$1
            local gpu_type=$2  # nvidia or amd

            if ! ${pkgs.curl}/bin/curl -s http://localhost:"$port" > /tmp/lolminer_"$gpu_type".json 2>/dev/null; then
              return
            fi

            {
              echo "# HELP mining_lolminer_hashrate_total Total hashrate for lolminer"
              echo "# TYPE mining_lolminer_hashrate_total gauge"
              HASHRATE=$(${pkgs.jq}/bin/jq -r '.hashrate_total[0] // 0' /tmp/lolminer_"$gpu_type".json 2>/dev/null || echo "0")
              echo "mining_lolminer_hashrate_total{instance=$HOST_LABEL,gpu_type=\"$gpu_type\"} $HASHRATE"

              echo "# HELP mining_lolminer_hashrate_per_gpu Hashrate per GPU"
              echo "# TYPE mining_lolminer_hashrate_per_gpu gauge"
              ${pkgs.jq}/bin/jq -r '.GPU[] | "mining_lolminer_hashrate_per_gpu{instance=\\\""'"$HOSTNAME"'\\\",gpu_type=\\\""'"$gpu_type"'\\\",gpu_id=\\\"" + (.gpu | tostring) + "\\\"} " + (.hashrate[0][0] // "0" | tostring)' /tmp/lolminer_"$gpu_type".json 2>/dev/null || true

              echo "# HELP mining_lolminer_shares_accepted Total accepted shares"
              echo "# TYPE mining_lolminer_shares_accepted counter"
              ACCEPTED=$(${pkgs.jq}/bin/jq -r '.Session.Shares[0] // 0' /tmp/lolminer_"$gpu_type".json 2>/dev/null || echo "0")
              echo "mining_lolminer_shares_accepted{instance=$HOST_LABEL,gpu_type=\"$gpu_type\"} $ACCEPTED"

              echo "# HELP mining_lolminer_shares_rejected Total rejected shares"
              echo "# TYPE mining_lolminer_shares_rejected counter"
              REJECTED=$(${pkgs.jq}/bin/jq -r '.Session.Shares[1] // 0' /tmp/lolminer_"$gpu_type".json 2>/dev/null || echo "0")
              echo "mining_lolminer_shares_rejected{instance=$HOST_LABEL,gpu_type=\"$gpu_type\"} $REJECTED"

              echo "# HELP mining_lolminer_uptime_seconds Uptime in seconds"
              echo "# TYPE mining_lolminer_uptime_seconds gauge"
              UPTIME=$(${pkgs.jq}/bin/jq -r '.Session.Uptime // 0' /tmp/lolminer_"$gpu_type".json 2>/dev/null || echo "0")
              echo "mining_lolminer_uptime_seconds{instance=$HOST_LABEL,gpu_type=\"$gpu_type\"} $UPTIME"

              echo "# HELP mining_lolminer_power_watts Power consumption"
              echo "# TYPE mining_lolminer_power_watts gauge"
              ${pkgs.jq}/bin/jq -r '.GPU[] | "mining_lolminer_power_watts{instance=\\\""'"$HOSTNAME"'\\\",gpu_type=\\\""'"$gpu_type"'\\\",gpu_id=\\\"" + (.gpu | tostring) + "\\\"} " + (.power // "0" | tostring)' /tmp/lolminer_"$gpu_type".json 2>/dev/null || true

              echo "# HELP mining_lolminer_temperature_celsius GPU temperature"
              echo "# TYPE mining_lolminer_temperature_celsius gauge"
              ${pkgs.jq}/bin/jq -r '.GPU[] | "mining_lolminer_temperature_celsius{instance=\\\""'"$HOSTNAME"'\\\",gpu_type=\\\""'"$gpu_type"'\\\",gpu_id=\\\"" + (.gpu | tostring) + "\\\"} " + (.temperature // "0" | tostring)' /tmp/lolminer_"$gpu_type".json 2>/dev/null || true

              echo ""
            } >> "$METRICS_FILE"
          }

          # Fetch xmrig metrics (appends to METRICS_FILE)
          fetch_xmrig() {
            local port=$1

            if ! ${pkgs.curl}/bin/curl -s http://localhost:"$port"/1/summary > /tmp/xmrig.json 2>/dev/null; then
              return
            fi

            {
              echo "# HELP mining_xmrig_hashrate_total Total hashrate for xmrig"
              echo "# TYPE mining_xmrig_hashrate_total gauge"
              HASHRATE=$(${pkgs.jq}/bin/jq -r '.hashrate.total[0] // 0' /tmp/xmrig.json 2>/dev/null || echo "0")
              echo "mining_xmrig_hashrate_total{instance=$HOST_LABEL} $HASHRATE"

              echo "# HELP mining_xmrig_hashrate_per_thread Hashrate per thread"
              echo "# TYPE mining_xmrig_hashrate_per_thread gauge"
              ${pkgs.jq}/bin/jq -r '.hashrate.threads[] | "mining_xmrig_hashrate_per_thread{instance=\\\""'"$HOSTNAME"'\\\",thread_id=\\\"" + (.thread | tostring) + "\\\"} " + ([.[0]] | tostring)' /tmp/xmrig.json 2>/dev/null || true

              echo "# HELP mining_xmrig_shares_accepted Total accepted shares"
              echo "# TYPE mining_xmrig_shares_accepted counter"
              ACCEPTED=$(${pkgs.jq}/bin/jq -r '.results.shares_good // 0' /tmp/xmrig.json 2>/dev/null || echo "0")
              echo "mining_xmrig_shares_accepted{instance=$HOST_LABEL} $ACCEPTED"

              echo "# HELP mining_xmrig_shares_rejected Total rejected shares"
              echo "# TYPE mining_xmrig_shares_rejected counter"
              REJECTED=$(${pkgs.jq}/bin/jq -r '.results.shares_total // .results.shares_good // 0' /tmp/xmrig.json 2>/dev/null)
              REJECTED=$((REJECTED - ACCEPTED))
              echo "mining_xmrig_shares_rejected{instance=$HOST_LABEL} $REJECTED"

              echo "# HELP mining_xmrig_uptime_seconds Uptime in seconds"
              echo "# TYPE mining_xmrig_uptime_seconds gauge"
              UPTIME=$(${pkgs.jq}/bin/jq -r '.worker.connection_time // 0' /tmp/xmrig.json 2>/dev/null || echo "0")
              echo "mining_xmrig_uptime_seconds{instance=$HOST_LABEL} $UPTIME"

              echo "# HELP mining_xmrig_threads Active mining threads"
              echo "# TYPE mining_xmrig_threads gauge"
              THREADS=$(${pkgs.jq}/bin/jq -r '.hashrate.threads | length' /tmp/xmrig.json 2>/dev/null || echo "0")
              echo "mining_xmrig_threads{instance=$HOST_LABEL} $THREADS"

              echo "# HELP mining_xmrig_cpu_percent CPU usage percentage"
              echo "# TYPE mining_xmrig_cpu_percent gauge"
              CPU=$(${pkgs.jq}/bin/jq -r '.resources.cpu_percent // 0' /tmp/xmrig.json 2>/dev/null || echo "0")
              echo "mining_xmrig_cpu_percent{instance=$HOST_LABEL} $CPU"

              echo ""
            } >> "$METRICS_FILE"
          }

          # Main scraping loop
          echo "Starting mining exporter on port $PORT"
          echo "Scraping mining APIs every $INTERVAL_SECONDS seconds"

          # Create final metrics file location
          FINAL_METRICS="$METRICS_DIR/metrics"

          # Update metrics function
          update_metrics() {
            # Start fresh metrics file
            > "$METRICS_FILE"
            echo "# Generated at $(${pkgs.coreutils}/bin/date -Iseconds)" >> "$METRICS_FILE"
            echo "" >> "$METRICS_FILE"

            # Fetch all metrics
            ${lib.optionalString (
            hostConfig.nvidia && hostConfig ? lolminerPort
          ) "fetch_lolminer ${toString hostConfig.lolminerPort} nvidia"}
            ${lib.optionalString (
            hostConfig.amd && hostConfig ? lolminerAmdPort
          ) "fetch_lolminer ${toString hostConfig.lolminerAmdPort} amd"}
            ${lib.optionalString hostConfig.cpu "fetch_xmrig ${toString hostConfig.xmrigPort}"}

            # Atomic move to final location
            mv "$METRICS_FILE" "$FINAL_METRICS"
          }

          # Initial fetch
          update_metrics

          # Start HTTP server in background and continue scraping
          # Use pre-written Python script with correct Content-Type header
          ${pkgs.python3}/bin/python3 ${httpServerScript} "$PORT" "$FINAL_METRICS" &
          SERVER_PID=$!

          # Scrape loop
          while true; do
            sleep "$INTERVAL_SECONDS"
            update_metrics
          done

          # Cleanup
          kill $SERVER_PID 2>/dev/null || true
        '';

        Restart = "always";
        RestartSec = "10s";
        StandardOutput = "journal";
        StandardError = "journal";

        # Security
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = "/";
        ReadWritePaths = "/run/prometheus/mining-exporter";
      };
    };

    # Open firewall port for Prometheus scraping
    # Allow from both Tailscale VPN and local network
    networking.firewall.allowedTCPPorts = [cfg.port];
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [cfg.port];
  };
}
