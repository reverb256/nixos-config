# Alert Webhook Receiver
# Receives AlertManager webhooks and displays desktop notifications
# No authentication required - runs locally on the cluster
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.monitoring.alert-webhook;
in {
  options.services.monitoring.alert-webhook = {
    enable = lib.mkEnableOption "Local webhook receiver for AlertManager alerts";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9099;
      description = "Port for the webhook receiver";
    };

    enableDesktopNotify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable desktop notifications for alerts";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/alert-webhook/alerts.log";
      description = "Log file for received alerts";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create log directory
    systemd.tmpfiles.rules = [
      "d /var/log/alert-webhook 0755 root root -"
      "d /var/log/alert-webhook/archive 0755 root root -"
    ];

    # Python webhook receiver
    environment.etc."alert-webhook/receiver.py".text = ''
      #!/usr/bin/env python3
      """Local webhook receiver for AlertManager alerts."""
      import json
      import logging
      from datetime import datetime
      from http.server import HTTPServer, BaseHTTPRequestHandler
      from socketserver import ThreadingMixIn
      from pathlib import Path

      # Configuration
      PORT = ${toString cfg.port}
      LOG_FILE = "${cfg.logFile}"
      ENABLE_DESKTOP_NOTIFY = ${toString cfg.enableDesktopNotify}

      # Setup logging
      logging.basicConfig(
          level=logging.INFO,
          format="%(asctime)s - %(message)s",
          handlers=[
              logging.FileHandler(LOG_FILE),
              logging.StreamHandler()
          ]
      )
      logger = logging.getLogger(__name__)

      class AlertHandler(BaseHTTPRequestHandler):
          def log_message(self, format, *args):
              logger.info(f"{self.address_string()} - {format % args}")

          def send_response(self, code, message=""):
              super().send_response(code)
              self.send_header("Content-Type", "text/plain")
              self.end_headers()
              if message:
                  self.wfile.write(message.encode())

          def do_GET(self):
              if self.path == "/health":
                  self.send_response(200, "OK\n")
              else:
                  self.send_response(404, "Not Found\n")

          def do_POST(self):
              if self.path == "/alerts":
                  content_length = int(self.headers.get("Content-Length", 0))
                  body = self.rfile.read(content_length)

                  try:
                      alerts = json.loads(body.decode())
                      self.process_alerts(alerts)
                      self.send_response(200, "OK\n")
                  except json.JSONDecodeError as e:
                      logger.error(f"Failed to parse JSON: {e}")
                      self.send_response(400, "Bad JSON\n")
                  except Exception as e:
                      logger.error(f"Error processing alerts: {e}")
                      self.send_response(500, "Internal Error\n")
              else:
                  self.send_response(404, "Not Found\n")

          def process_alerts(self, data):
              """Process incoming alerts from AlertManager."""
              alerts = data.get("alerts", [])
              receiver = data.get("receiver", "unknown")

              for alert in alerts:
                  self.handle_alert(alert, receiver)

          def handle_alert(self, alert, receiver):
              """Handle a single alert."""
              status = alert.get("status", "firing")
              labels = alert.get("labels", {})
              annotations = alert.get("annotations", {})

              alertname = labels.get("alertname", "unknown")
              severity = labels.get("severity", "warning")
              instance = labels.get("instance", "")
              job = labels.get("job", "")

              # Build message
              summary = annotations.get("summary", f"{alertname} is {status}")
              description = annotations.get("description", "")

              message = f"[{severity.upper()}] {summary}"
              if description:
                  message += f" - {description}"
              if instance:
                  message += f" (instance: {instance})"

              # Log the alert
              logger.info(f"Alert: {message}")

              # Send desktop notification
              if ENABLE_DESKTOP_NOTIFY and status == "firing":
                  self.send_notification(
                      title=f"Alert: {alertname}",
                      body=message,
                      urgency=severity
                  )

          def send_notification(self, title, body, urgency="warning"):
              """Send desktop notification using notify-send."""
              import subprocess

              # Map urgency to notify-send levels
              urgency_map = {
                  "critical": "critical",
                  "error": "normal",
                  "warning": "normal",
                  "info": "low"
              }
              notify_urgency = urgency_map.get(urgency.lower(), "normal")

              try:
                  subprocess.run([
                      "${pkgs.libnotify}/bin/notify-send",
                      "-u", notify_urgency,
                      "-i", "dialog-warning",
                      "-a", "AlertManager",
                      title,
                      body
                  ], check=False, timeout=5)
              except Exception as e:
                  logger.error(f"Failed to send notification: {e}")

      class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
          daemon_threads = True

      def main():
          server = ThreadedHTTPServer(("127.0.0.1", PORT), AlertHandler)
          logger.info(f"Alert webhook receiver listening on http://127.0.0.1:{PORT}")
          server.serve_forever()

      if __name__ == "__main__":
          main()
    '';

    # Systemd service
    systemd.services.alert-webhook = {
      description = "AlertManager Webhook Receiver";
      after = ["network.target" "alertmanager.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe pkgs.python3 + " /etc/alert-webhook/receiver.py";
        Restart = "on-failure";
        RestartSec = "10s";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];

        # Allow writing to log directory
        ReadWritePaths = ["/var/log/alert-webhook"];
      };
    };

    # Open firewall for localhost only (not needed for 127.0.0.1 binding)
    # networking.firewall.allowedTCPPorts = [cfg.port]; # Only local, no firewall needed

    # Add to system packages
    environment.systemPackages = with pkgs; [
      python3
      libnotify # For notify-send desktop notifications
    ];
  };
}
