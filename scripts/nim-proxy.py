#!/run/current-system/sw/bin/python3
"""nim-proxy: self-learning NVIDIA NIM rate limiter with AIMD congestion control.

Learns the actual rate limits by observing real API behavior:
- On success → slowly increase allowed rate (additive increase)
- On 429 → back off aggressively (multiplicative decrease)
- No hardcoded RPM/TPM ceilings — discovers them dynamically.

Also implements circuit breaker, exponential backoff, and a /metrics endpoint.
"""

import json, logging, os, random, tempfile, threading, time, urllib.request
from dataclasses import dataclass, field
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from typing import Optional

log = logging.getLogger("nim-proxy")

# ─── Configuration ────────────────────────────────────────────────────────────

START_RPM   = int(os.environ.get("START_RPM",   "20"))
MIN_RPM     = int(os.environ.get("MIN_RPM",     "5"))
START_TPM   = int(os.environ.get("START_TPM",   "50000"))
MIN_TPM     = int(os.environ.get("MIN_TPM",     "10000"))
AI_STEP     = float(os.environ.get("AI_RPM_STEP", "1"))
MD_FACTOR   = float(os.environ.get("MD_FACTOR",  "0.5"))
WINDOW_MS   = 60_000
CB_THRESHOLD = int(os.environ.get("CB_THRESHOLD", "5"))
CB_COOLDOWN  = int(os.environ.get("CB_COOLDOWN",  "3600"))
STATE_FILE  = os.environ.get("STATE_FILE", "/home/j_kro/.cache/nim-proxy-state.json")
HOST = os.environ.get("PROXY_HOST", "127.0.0.1")
PORT = int(os.environ.get("PROXY_PORT", "8787"))
NVIDIA_KEY = os.environ.get("NVIDIA_API_KEY", "")
NVIDIA_BASE = "https://integrate.api.nvidia.com"


def positive_int_env(name: str, default: str) -> int:
    raw = os.environ.get(name, default)
    try:
        value = int(raw)
    except ValueError as e:
        raise ValueError(f"{name} must be a positive integer, got {raw!r}") from e
    if value < 1:
        raise ValueError(f"{name} must be a positive integer, got {value}")
    return value


MAX_CONCURRENCY = positive_int_env("MAX_CONCURRENCY", "4")
NIM_SLOTS = threading.BoundedSemaphore(MAX_CONCURRENCY)

@dataclass
class AIMDController:
    rpm_target: float = START_RPM
    tpm_target: float = START_TPM
    rpm_entries: list = field(default_factory=list)
    tpm_entries: list = field(default_factory=list)
    last_request_ms: float = 0
    consecutive_429: int = 0
    circuit_opened_at: Optional[float] = None
    window_ms: int = WINDOW_MS
    _lock: threading.RLock = field(default_factory=threading.RLock, init=False,
                                   repr=False)

    def prune(self, entries: list, now: int) -> None:
        with self._lock:
            cutoff = now - self.window_ms
            while entries and entries[0][0] < cutoff:
                entries.pop(0)

    @property
    def rpm_window_count(self) -> int:
        with self._lock:
            self.prune(self.rpm_entries, int(time.time() * 1000))
            return len(self.rpm_entries)

    def record_success(self, tokens: int = 0) -> None:
        with self._lock:
            now = int(time.time() * 1000)
            self.rpm_entries.append((now, 1))
            if tokens:
                self.tpm_entries.append((now, tokens))
            self.last_request_ms = now
            self.consecutive_429 = 0
            self.circuit_opened_at = None
            self.rpm_target = min(self.rpm_target + AI_STEP, self.rpm_target * 1.02)
            self.tpm_target = min(self.tpm_target + 100, self.tpm_target * 1.01)
            self._save()

    def record_429(self) -> None:
        with self._lock:
            self.consecutive_429 += 1
            self.rpm_target = max(self.rpm_target * MD_FACTOR, MIN_RPM)
            self.tpm_target = max(self.tpm_target * MD_FACTOR, MIN_TPM)
            if self.consecutive_429 >= CB_THRESHOLD and self.circuit_opened_at is None:
                self.circuit_opened_at = time.monotonic()
                log.warning("CIRCUIT OPEN — %d consecutive 429s", self.consecutive_429)
            self._save()

    @property
    def circuit_remaining(self) -> int:
        with self._lock:
            if self.circuit_opened_at is None:
                return 0
            e = time.monotonic() - self.circuit_opened_at
            if e >= CB_COOLDOWN:
                self.circuit_opened_at = None
                self.consecutive_429 = 0
                return 0
            return int(CB_COOLDOWN - e)

    def can_send(self, now: int) -> Optional[str]:
        with self._lock:
            if self.circuit_opened_at is not None:
                e = time.monotonic() - self.circuit_opened_at
                if e < CB_COOLDOWN:
                    return f"circuit_breaker:{int(CB_COOLDOWN - e)}s"
                self.circuit_opened_at = None
                self.consecutive_429 = 0
            self.prune(self.rpm_entries, now)
            if len(self.rpm_entries) >= int(self.rpm_target):
                return f"rpm_limit:{int(self.rpm_target)}/min"
            d = int(WINDOW_MS / max(self.rpm_target, MIN_RPM))
            e = now - self.last_request_ms
            if e < d and self.last_request_ms > 0:
                return f"inter_request_delay:{d - e}ms"
            return None

    def _save(self) -> None:
        with self._lock:
            directory = os.path.dirname(STATE_FILE) or "."
            temporary = None
            fd = None
            try:
                os.makedirs(directory, exist_ok=True)
                fd, temporary = tempfile.mkstemp(prefix=".nim-proxy-",
                                                 dir=directory, text=True)
                state = os.fdopen(fd, "w", encoding="utf-8")
                fd = None
                with state:
                    json.dump({"rpm_target": self.rpm_target,
                               "tpm_target": self.tpm_target,
                               "consecutive_429": self.consecutive_429}, state)
                    state.flush()
                    os.fsync(state.fileno())
                os.replace(temporary, STATE_FILE)
                temporary = None
            except Exception as e:
                log.warning("Could not persist NIM proxy state: %s", e)
            finally:
                if fd is not None:
                    try:
                        os.close(fd)
                    except OSError:
                        pass
                if temporary is not None:
                    try:
                        os.unlink(temporary)
                    except OSError:
                        pass

    @classmethod
    def load(cls) -> "AIMDController":
        try:
            with open(STATE_FILE, encoding="utf-8") as state:
                d = json.load(state)
            log.info("Loaded: rpm=%.1f tpm=%.0f", d["rpm_target"], d["tpm_target"])
            return cls(rpm_target=d["rpm_target"], tpm_target=d["tpm_target"],
                       consecutive_429=d.get("consecutive_429", 0))
        except (FileNotFoundError, json.JSONDecodeError):
            log.info("Fresh start: rpm=%.0f tpm=%.0f", START_RPM, START_TPM)
            return cls()

ctl = AIMDController.load()

class Handler(BaseHTTPRequestHandler):
    def _ok_or_429(self) -> bool:
        r = ctl.can_send(int(time.time() * 1000))
        if r is None:
            return True
        log.info("Blocked: %s", r)
        self._json(429, {"error": {"message": f"NIM proxy: {r}", "type": "rate_limit_error"}})
        return False

    def _json(self, s: int, d: dict):
        b = json.dumps(d).encode()
        self.send_response(s)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"status": "ok", "service": "nim-proxy",
                             "rpm_learned": round(ctl.rpm_target, 1),
                             "rpm_window": ctl.rpm_window_count,
                             "circuit": ctl.circuit_remaining})
        elif self.path == "/metrics":
            self._json(200, {"rpm_target": round(ctl.rpm_target, 1),
                             "rpm_window": ctl.rpm_window_count,
                             "tpm_target": round(ctl.tpm_target),
                             "consecutive_429": ctl.consecutive_429,
                             "circuit_remaining": ctl.circuit_remaining})
        else:
            self._proxy(b"")

    def do_POST(self):
        if self.path not in ("/v1/chat/completions", "/v1/completions", "/v1/embeddings"):
            return self._json(404, {"error": "not_found"})
        l = int(self.headers.get("Content-Length", 0))
        self._proxy(self.rfile.read(l) if l else b"{}")

    def _proxy(self, body: bytes):
        if not self._ok_or_429():
            return
        if not NIM_SLOTS.acquire(blocking=False):
            self._json(429, {"error": {"message": "NIM proxy concurrency limit reached", "type": "rate_limit_error"}})
            return
        try:
            req = urllib.request.Request(f"{NVIDIA_BASE}{self.path}", data=body,
                headers={"Authorization": f"Bearer {NVIDIA_KEY}", "Content-Type": "application/json"},
                method=self.command)
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    rb = r.read()
                    t = 0
                    try:
                        u = json.loads(rb).get("usage", {}); t = u.get("total_tokens", 0) if u else 0
                    except Exception: pass
                    ctl.record_success(t)
                    self.send_response(r.status)
                    for k, v in r.headers.items():
                        if k.lower() not in ("transfer-encoding", "content-encoding", "content-length"):
                            self.send_header(k, v)
                    self.send_header("Content-Length", str(len(rb))); self.end_headers(); self.wfile.write(rb)
            except urllib.error.HTTPError as e:
                rb = e.read()
                if e.code == 429: ctl.record_429(); log.warning("429 — rpm=%.1f fails=%d", ctl.rpm_target, ctl.consecutive_429)
                else: log.error("NIM %d: %s", e.code, rb[:200])
                self.send_response(e.code); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(rb)
            except urllib.error.URLError as e:
                log.error("NIM down: %s", e.reason); self._json(502, {"error": {"message": f"NIM unreachable: {e.reason}"}})
            except Exception as e:
                log.error("Proxy: %s", e); self._json(500, {"error": {"message": str(e)}})

        finally:
            NIM_SLOTS.release()

def main():
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO").upper(),
                        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    log.info("nim-proxy on %s:%s — rpm_start=%.0f tpm_start=%.0f state=%s",
             HOST, PORT, ctl.rpm_target, ctl.tpm_target, STATE_FILE)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()

if __name__ == "__main__":
    main()
