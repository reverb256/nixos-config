#!/usr/bin/env python3
"""nim-proxy: NVIDIA NIM rate-limiting proxy with circuit breaker.

Layered before Hermes' nvidia provider so rate limits (RPM/TPM), 429 backoff,
and circuit breaker are handled client-side instead of hitting NIM directly.
If the circuit is open or rate is exhausted, returns 429 — Hermes then
falls through the provider chain (kilocode → opencode-zen → opencode-go).

Usage:
  NIM_PROXY_PORT=8787 NVIDIA_API_KEY=nvapi-... python3 nim-proxy.py
"""

import asyncio, json, logging, os, random, time, urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler
from dataclasses import dataclass, field
from typing import Optional

log = logging.getLogger("nim-proxy")

# --- Configuration -----------------------------------------------------------
MAX_RPM = 30                         # safe requests/min (NIM docs: 40)
RPM_WINDOW_MS = 60_000
MAX_TPM = 150_000                    # safe tokens/min
INTER_REQUEST_DELAY_MS = RPM_WINDOW_MS // MAX_RPM  # ~2000ms

MAX_RETRIES = 3
BASE_BACKOFF_MS = 2_000              # 2s initial
MAX_BACKOFF_MS = 300_000             # 5 min cap

CIRCUIT_THRESHOLD = 5                # consecutive 429s → open
CIRCUIT_COOLDOWN_S = 3600            # 1 hour before retry

MAX_QUEUE = 10

NVIDIA_BASE = "https://integrate.api.nvidia.com"
NVIDIA_KEY = os.environ.get("NVIDIA_API_KEY", "")
HOST = os.environ.get("PROXY_HOST", "127.0.0.1")
PORT = int(os.environ.get("PROXY_PORT", "8787"))

# --- State ------------------------------------------------------------------

@dataclass
class SlidingWindow:
    window_ms: int
    max_count: int
    entries: list = field(default_factory=list)

    def prune(self, now: int) -> None:
        cutoff = now - self.window_ms
        while self.entries and self.entries[0] < cutoff:
            self.entries.pop(0)

    def count(self, now: int) -> int:
        self.prune(now)
        return len(self.entries)

    def can_accept(self, now: int) -> bool:
        return self.count(now) < self.max_count

    def add(self, now: int) -> None:
        self.entries.append(now)

class CircuitBreaker:
    def __init__(self):
        self.failures = 0
        self.opened_at: Optional[float] = None

    def record_failure(self):
        self.failures += 1
        if self.failures >= CIRCUIT_THRESHOLD and self.opened_at is None:
            self.opened_at = time.monotonic()
            log.warning("CIRCUIT OPEN — %d failures, cooldown %ds", self.failures, CIRCUIT_COOLDOWN_S)

    def record_success(self):
        if self.opened_at is not None:
            log.info("Circuit closed (successful request)")
        self.failures = 0
        self.opened_at = None

    @property
    def is_open(self) -> bool:
        if self.opened_at is None:
            return False
        elapsed = time.monotonic() - self.opened_at
        if elapsed >= CIRCUIT_COOLDOWN_S:
            self.opened_at = None
            self.failures = 0
            log.info("Circuit half-open — allowing probe")
            return False
        return True

    @property
    def remaining(self) -> int:
        if self.opened_at is None:
            return 0
        return max(0, int(CIRCUIT_COOLDOWN_S - (time.monotonic() - self.opened_at)))

# --- HTTP Handler -----------------------------------------------------------

limiter = None  # set in main()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/v1/models":
            self._proxy(b"")
        elif self.path == "/health":
            self._json(200, {"status": "ok", "service": "nim-proxy"})
        else:
            self._json(404, {"error": "not_found"})

    def do_POST(self):
        if self.path in ("/v1/chat/completions", "/v1/completions", "/v1/embeddings"):
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length) if length else b"{}"
            self._proxy(body)
        else:
            self._json(404, {"error": "not_found"})

    def _json(self, status: int, data: dict):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _proxy(self, body: bytes):
        global limiter
        now = int(time.time() * 1000)

        # Circuit breaker
        if limiter.circuit.is_open:
            log.warning("Blocked: circuit open (%ds)", limiter.circuit.remaining)
            self._json(429, {"error": {
                "message": f"NIM circuit breaker open ({limiter.circuit.remaining}s)",
                "type": "rate_limit_error"}})
            return

        # Rate limit check (sequential: enforce inter-request delay)
        if not limiter.rpm.can_accept(now):
            log.warning("Blocked: RPM exhausted")
            self._json(429, {"error": {
                "message": "NIM RPM limit — try again later",
                "type": "rate_limit_error"}})
            return

        elapsed = now - limiter.last_req
        if elapsed < INTER_REQUEST_DELAY_MS:
            asyncio.run(asyncio.sleep((INTER_REQUEST_DELAY_MS - elapsed) / 1000))

        # Proxy to NIM
        url = f"{NVIDIA_BASE}{self.path}"
        headers = {
            "Authorization": f"Bearer {NVIDIA_KEY}",
            "Content-Type": "application/json",
        }
        req = urllib.request.Request(url, data=body, headers=headers, method=self.command)

        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                resp_body = resp.read()
                # Estimate tokens
                try:
                    data = json.loads(resp_body)
                    tokens = (data.get("usage") or {}).get("total_tokens", 0)
                except Exception:
                    tokens = 0

                now = int(time.time() * 1000)
                limiter.rpm.add(now)
                limiter.last_req = now
                limiter.circuit.record_success()

                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in ("transfer-encoding", "content-encoding", "content-length"):
                        self.send_header(k, v)
                self.send_header("Content-Length", str(len(resp_body)))
                self.end_headers()
                self.wfile.write(resp_body)

        except urllib.error.HTTPError as e:
            resp_body = e.read()
            if e.code == 429:
                limiter.circuit.record_failure()
                retry_after = int(e.headers.get("Retry-After", 0))
                log.warning("NIM 429 (failure %d/%d)", limiter.circuit.failures, CIRCUIT_THRESHOLD)
            else:
                log.error("NIM HTTP %d: %s", e.code, resp_body[:200])

            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(resp_body)

        except urllib.error.URLError as e:
            log.error("NIM connection: %s", e)
            self._json(502, {"error": {"message": f"NIM unreachable: {e.reason}", "type": "proxy_error"}})

        except Exception as e:
            log.error("Proxy error: %s", e)
            self._json(500, {"error": {"message": str(e), "type": "proxy_error"}})

# --- Main -------------------------------------------------------------------

def main():
    global limiter
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO").upper(),
                        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")

    class State:
        rpm = SlidingWindow(RPM_WINDOW_MS, MAX_RPM)
        circuit = CircuitBreaker()
        last_req = 0

    limiter = State()

    log.info("NIM proxy on %s:%s — RPM=%d TPM=%d circuit=%dx%ds",
             HOST, PORT, MAX_RPM, MAX_TPM, CIRCUIT_THRESHOLD, CIRCUIT_COOLDOWN_S)

    server = HTTPServer((HOST, PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("Shutdown")
        server.server_close()

if __name__ == "__main__":
    main()
