#!/usr/bin/env python3
"""PeakMiner Prometheus metrics exporter.

Scrapes the local PeakMiner /summary endpoint and exposes
Prometheus-format metrics on a configurable HTTP port.
"""
import http.server
import json
import os
import urllib.request
import sys

TARGET_PORT = int(os.environ.get("PEAKMINER_API_PORT", "21553"))
EXPORTER_PORT = int(os.environ.get("EXPORTER_PORT", str(TARGET_PORT + 10000)))
WORKER_NAME = os.environ.get("WORKER_NAME", "unknown")

PEAKMINER_URL = f"http://127.0.0.1:{TARGET_PORT}/summary"

METRICS_HEADER = """# HELP peakminer_up Whether the PeakMiner API is reachable (1=up, 0=down)
# TYPE peakminer_up gauge
# HELP peakminer_hashrate Current hashrate in H/s
# TYPE peakminer_hashrate gauge
# HELP peakminer_accepted_shares Total accepted shares
# TYPE peakminer_accepted_shares counter
# HELP peakminer_invalid_shares Total invalid shares
# TYPE peakminer_invalid_shares counter
# HELP peakminer_efficiency_percent Share efficiency percentage
# TYPE peakminer_efficiency_percent gauge
# HELP peakminer_gpu_temperature GPU temperature in Celsius
# TYPE peakminer_gpu_temperature gauge
# HELP peakminer_gpu_power_watts GPU power draw in watts
# TYPE peakminer_gpu_power_watts gauge
# HELP peakminer_gpu_fan_percent GPU fan speed percentage
# TYPE peakminer_gpu_fan_percent gauge
# HELP peakminer_gpu_core_clock GPU core clock in MHz
# TYPE peakminer_gpu_core_clock gauge
# HELP peakminer_gpu_mem_clock GPU memory clock in MHz
# TYPE peakminer_gpu_mem_clock gauge
"""


def scrape_metrics() -> str:
    try:
        req = urllib.request.Request(PEAKMINER_URL, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
    except Exception:
        return f"{METRICS_HEADER}peakminer_up{{worker=\"{WORKER_NAME}\"}} 0\n"

    lines = [METRICS_HEADER]
    lines.append(f'peakminer_up{{worker="{WORKER_NAME}"}} 1')

    hr = data.get("hashrate", 0)
    lines.append(f'peakminer_hashrate{{worker="{WORKER_NAME}"}} {hr}')
    lines.append(f'peakminer_accepted_shares{{worker="{WORKER_NAME}"}} {data.get("accepted_shares", 0)}')
    lines.append(f'peakminer_invalid_shares{{worker="{WORKER_NAME}"}} {data.get("invalid_shares", 0)}')
    lines.append(f'peakminer_efficiency_percent{{worker="{WORKER_NAME}"}} {data.get("efficiency_pct", 0)}')

    for gpu in data.get("gpus", []):
        gpu_name = gpu.get("name", "unknown").replace(" ", "_")
        gpu_label = f'worker="{WORKER_NAME}",gpu="{gpu_name}"'
        lines.append(f'peakminer_gpu_temperature{{{gpu_label}}} {gpu.get("temperature_c", 0)}')
        lines.append(f'peakminer_gpu_power_watts{{{gpu_label}}} {gpu.get("power_w", 0)}')
        lines.append(f'peakminer_gpu_fan_percent{{{gpu_label}}} {gpu.get("fan_pct", 0)}')
        lines.append(f'peakminer_gpu_core_clock{{{gpu_label}}} {gpu.get("core_clock_mhz", 0)}')
        lines.append(f'peakminer_gpu_mem_clock{{{gpu_label}}} {gpu.get("mem_clock_mhz", 0)}')

    return "\n".join(lines) + "\n"


class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            metrics = scrape_metrics()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(metrics.encode("utf-8"))
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"peakminer-exporter: use /metrics\n")

    def log_message(self, fmt, *args):
        pass  # quiet


if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", EXPORTER_PORT), MetricsHandler)
    print(f"PeakMiner exporter listening on 0.0.0.0:{EXPORTER_PORT} → {PEAKMINER_URL}", flush=True)
    server.serve_forever()
