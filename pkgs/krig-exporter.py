#!/usr/bin/env python3
"""Krig Prometheus metrics exporter (proxy).

Krig (krig-miner) exposes a native Prometheus /metrics endpoint on its
--api-port. This tiny proxy re-serves that endpoint on a separate exporter
port so Prometheus (scraping from the k8s pod CIDR) does not need direct
reachability to each miner's localhost API. Keeps the on-disk metric names
(krig_miner_*) so dashboards keep working after the peakminer -> krig swap.

Env:
  KRIG_API_PORT    (int)   port Krig's /metrics listens on (localhost)
  EXPORTER_PORT    (int)   port this proxy listens on (0.0.0.0)
  WORKER_NAME      (str)   local instance label (systemd instance name)
"""
import http.server
import os
import socket
import urllib.request

KRIG_API_PORT = int(os.environ.get("KRIG_API_PORT", "21553"))
EXPORTER_PORT = int(os.environ.get("EXPORTER_PORT", str(KRIG_API_PORT + 10000)))
WORKER_NAME = os.environ.get("WORKER_NAME", "unknown")

KRIG_METRICS_URL = f"http://127.0.0.1:{KRIG_API_PORT}/metrics"


def scrape() -> bytes:
    try:
        req = urllib.request.Request(KRIG_METRICS_URL, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = resp.read()
        # If Krig is up it already emits krig_miner_up-style gauges; just proxy.
        return body
    except Exception:
        # Krig down: emit a single up=0 gauge keyed by our local worker name.
        return (
            f'# HELP krig_miner_up 1 if the Krig API is reachable, else 0\n'
            f'# TYPE krig_miner_up gauge\n'
            f'krig_miner_up{{worker="{WORKER_NAME}"}} 0\n'
        ).encode("utf-8")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            data = scrape()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"krig-exporter: use /metrics\n")

    def log_message(self, fmt, *args):
        pass  # quiet


if __name__ == "__main__":
    # Allow rapid reuse of the exporter port across restarts.
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    httpd = http.server.HTTPServer(("0.0.0.0", EXPORTER_PORT), Handler)
    print(
        f"Krig exporter listening on 0.0.0.0:{EXPORTER_PORT} -> {KRIG_METRICS_URL}",
        flush=True,
    )
    httpd.serve_forever()
