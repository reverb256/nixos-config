# Mining Metrics Exporter for Prometheus
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;

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
      xmrigPort = 8081;
    };
    nexus = {
      nvidia = true;
      amd = false;
      cpu = true;
      xmrigPort = 8081;
    };
    forge = {
      nvidia = true;
      amd = true;
      cpu = false;
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
in
{
  options.services.mining-exporter = {
    enable = mkEnableOption "Mining metrics exporter for Prometheus";

    port = mkOption {
      type = types.port;
      default = 9105;
      description = "Port for mining metrics exporter";
    };

    scrapeInterval = mkOption {
      type = types.str;
      default = "15s";
      description = "How often to poll mining APIs";
    };
  };

  config = mkIf (cfg.enable && hostConfig != null) {
    systemd.services.prometheus-mining-exporter = {
      description = "Prometheus Mining Metrics Exporter";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writers.writeBash "mining-exporter" ''
          set -euo pipefail

          PORT=${toString cfg.port}
          HOSTNAME="$(${pkgs.hostname}/bin/hostname)"
          INTERVAL_SECONDS=15

          METRICS_DIR="/run/prometheus-mining-exporter"
          cd "$METRICS_DIR"

          # Helper to escape labels
          escape_label() {
            ${pkgs.gnused}/bin/sed 's/"/\\"/g; s/[^a-zA-Z0-9:_]/_/g'
          }

          HOST_LABEL="'$(echo "$HOSTNAME" | escape_label):${toString cfg.port}'"

          # Temporary file for accumulating metrics
          METRICS_FILE="$METRICS_DIR/metrics.tmp"


          # Fetch xmrig metrics (appends to METRICS_FILE)
          fetch_xmrig() {
            local port=$1

            if ! ${pkgs.curl}/bin/curl -s http://localhost:"$port"/1/summary -H "Authorization: Bearer mining-exporter-token" > /tmp/xmrig.json 2>/dev/null; then
              return
            fi

            {
              echo "# HELP mining_xmrig_hashrate_total Total hashrate for xmrig"
              echo "# TYPE mining_xmrig_hashrate_total gauge"
              HASHRATE=$(${pkgs.jq}/bin/jq -r '.hashrate.total[0] // 0' /tmp/xmrig.json 2>/dev/null || echo "0")
              echo "mining_xmrig_hashrate_total{instance=$HOST_LABEL} $HASHRATE"

              echo "# HELP mining_xmrig_hashrate_per_thread Hashrate per thread"
              echo "# TYPE mining_xmrig_hashrate_per_thread gauge"
              ${pkgs.jq}/bin/jq -r --arg hostname "$HOSTNAME" '.hashrate.threads[] | "mining_xmrig_hashrate_per_thread{instance=\"" + $hostname + "\",thread=\"" + (.index | tostring) + "\"} " + (.hashrate // 0 | tostring)' /tmp/xmrig.json 2>/dev/null || true

              echo "# HELP mining_xmrig_shares_accepted Total accepted shares"
              echo "# TYPE mining_xmrig_shares_accepted counter"
              ACCEPTED=$(${pkgs.jq}/bin/jq -r '.shares.accepted // 0' /tmp/xmrig.json 2>/dev/null || echo "0")
              echo "mining_xmrig_shares_accepted{instance=$HOST_LABEL} $ACCEPTED"

              echo "# HELP mining_xmrig_shares_rejected Total rejected shares"
              echo "# TYPE mining_xmrig_shares_rejected counter"
              REJECTED=$(${pkgs.jq}/bin/jq -r '.shares.rejected // 0' /tmp/xmrig.json 2>/dev/null || echo "0")
              echo "mining_xmrig_shares_rejected{instance=$HOST_LABEL} $REJECTED"

              echo ""
            } >> "$METRICS_FILE"
          }

          # Main polling loop
          # Conditionally fetch metrics based on what's configured for this host
    };

    # Use firewall helper to open ports
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
  };
}
