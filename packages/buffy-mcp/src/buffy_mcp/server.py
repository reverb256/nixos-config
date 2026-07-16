"""
Buffy MCP Server — local port of Freebuff tool primitives.

Gives Hermes access to file picker, code search, bash, file IO,
tmux sessions, HTTP fetching, and SearXNG web search — entirely
locally. No cloud egress unless explicitly opted in.

Safety:
- Path deny-list enforced for read/write (no /etc/sudoers, /etc/shadow,
  /proc/, /sys/, /run/secrets/, *.sops.yaml, ~/.ssh/id_*).
- Bash: regex deny-list for catastrophic patterns ('rm -rf /', dd-to-disk,
  mkfs, fork bomb, chmod 777 /, curl|sh, wget|sh).
- HTTP: blocks requests to non-LAN destinations by default; re-checks
  after each redirect to prevent a 302 chain from leaking out of the cluster.
- All tool invocations logged to BUFFY_AUDIT_LOG (default
  ~/.hermes/audit/buffy-mcp.jsonl). Set to empty string to disable.
- Audit-log entries ARE REDACTED via _SECRET_REDACT_PATTERNS before write
  (Bearer tokens, common API-key env vars, /run/secrets/* paths, JWT, hex).

Bypass env vars (use with care):
- BUFFY_ALLOW_NON_LAN=1   — permit HTTP to internet destinations.
- BUFFY_ALLOW_HOME_DIRS=1 — let file_picker walk /home (off by default).
- BUFFY_AUDIT_LOG=        — set to empty string to disable audit logging.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path
from typing import Any

import libtmux
import requests
from fastmcp import FastMCP


mcp = FastMCP("buffy")

# ── Configuration ─────────────────────────────────────────────────────────
AUDIT_LOG = Path(
    os.getenv("BUFFY_AUDIT_LOG") or os.path.expanduser("~/.hermes/audit/buffy-mcp.jsonl")
)
NETWORK_ALLOW_NON_LAN = os.getenv("BUFFY_ALLOW_NON_LAN", "").lower() in ("1", "true", "yes")
NIXOS_DIR = os.getenv("BUFFY_NIXOS_DIR", "/etc/nixos")
HOME_DIR = os.getenv("BUFFY_HOME_DIR", "/home/j_kro")
SEARCH_TIMEOUT = int(os.getenv("BUFFY_SEARCH_TIMEOUT", "30"))
BASH_TIMEOUT = int(os.getenv("BUFFY_BASH_TIMEOUT", "120"))
SEARXNG_URL = os.getenv("SEARXNG_URL", "http://searxng.search.svc.cluster.local:8080")

# ── Safety deny-lists ─────────────────────────────────────────────────────
DENY_PATH_PREFIXES = (
    "/etc/sudoers",
    "/etc/sudoers.d/",
    "/etc/shadow",
    "/etc/gshadow",
    "/proc/",
    "/sys/",
    "/run/secrets/",  # SOPS-decrypted secret mountpoints (write denied)
)
DENY_PATH_SUFFIXES = (
    ".sops.yaml",  # SOPS config plaintext
)
DENY_PATH_PATTERNS = (
    re.compile(r"/\.ssh/id_[a-z]+"),
)
DENY_BASH_PATTERNS = (
    re.compile(r"\brm\s+-[rRfF]*\s+/\s*(?:$|\s|;|\|)"),         # rm -rf / at root
    re.compile(r"\bdd\b.*\bof=/dev/(?:sd|nvme|hd|mmc|loop)"),     # dd to disk device
    re.compile(r"\bmkfs(?:\.\w+)?\s+/dev/"),                     # mkfs on device
    re.compile(r":\(\)\s*\{.*:\s*\|.*\};\s*:"),                 # fork bomb
    re.compile(r"\bchmod\s+(?:-R\s+)?777\s+/"),                  # chmod 777 /
    re.compile(r"\bcurl\b[^|]*\|\s*(?:ba)?sh\b"),                # curl | sh
    re.compile(r"\bwget\b[^|]*\|\s*(?:ba)?sh\b"),                # wget | sh
)
LAN_URL_RE = re.compile(
    r"^https?://"
    r"(?:127\.|10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\."      # RFC1918
    r"|::1"                                                      # IPv6 loopback
    r"|[a-z0-9-]+\.lan(?::\d+)?)"                                # .lan domains
)

# ── Secret-redaction (audit log hardening) ────────────────────────────────
# Conservative patterns. Audit-log entries pass through BEFORE json.dump.
# Add a provider's API key by appending a literal regex here when you
# onboard it. Tokens with high entropy that look like JWTs/cookies are
# also caught by the final two patterns.
_SECRET_REDACT_PATTERNS: tuple = (
    (re.compile(r"Authorization:\s*Bearer\s+[A-Za-z0-9._\-+/=]+"),
     "Authorization: Bearer <redacted>"),
    (re.compile(r"(?i)\b(api[_-]?key|password|secret|token)\s*[=:]\s*['\"]?[^\s'\"]{8,}"),
     r"\1=<redacted>"),
    (re.compile(r"\b(?:|NVIDIA|GITHUB|HUGGINGFACE|OPENCODE|GEMINI|XAI|KILO|POLLINATIONS|TAILSCALE|N8N|KATZILLA|HOMEBASE|HERMES|GITEA|GARAGE|VAULTWARDEN|MISSION)_API_KEY\s*=\s*\S+"),
     "<redacted-API-KEY>=<redacted>"),
    (re.compile(r"/run/secrets/[\w./-]+"), "/run/secrets/<redacted-path>"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}"), "<jwt>"),
    (re.compile(r"\b[a-f0-9]{32,}\b"), "<hex-token>"),
)
# Permissive prompt heuristic. Matches real-world PS1 patterns including
# [user@host:~/path]$#, root@forge /etc/nixos#, bare $, #, etc.
# Currency-line false-positives ('$100.00') are an accepted trade-off
# vs. the alternative of always sleeping the full timeout.
PROMPT_RE = re.compile(r".*[\$#]\s*$")


def _redact(text: str) -> str:
    """Apply secret-redaction patterns. Order matters: more specific first."""
    for pat, repl in _SECRET_REDACT_PATTERNS:
        text = pat.sub(repl, text)
    return text


# ── Helpers ───────────────────────────────────────────────────────────────
def _audit(tool: str, args: dict, result_summary: str) -> None:
    """Best-effort audit line with secret redaction. Never raises."""
    if not str(AUDIT_LOG):
        return
    try:
        AUDIT_LOG.parent.mkdir(parents=True, exist_ok=True)
        with AUDIT_LOG.open("a") as f:
            entry = {
                "ts": time.time(),
                "tool": tool,
                "args": {k: _redact(str(v))[:200] for k, v in args.items()},
                "result": _redact(result_summary)[:200],
            }
            f.write(json.dumps(entry) + "\n")
    except Exception:
        pass


def _is_path_denied(path: str) -> str | None:
    """Return reason string if path is denied, else None."""
    try:
        p = str(Path(path).resolve(strict=False))
    except (OSError, ValueError):
        return f"path is not resolvable: {path!r}"
    for prefix in DENY_PATH_PREFIXES:
        if p.startswith(prefix):
            return f"path starts with denied prefix {prefix!r}"
    for suffix in DENY_PATH_SUFFIXES:
        if p.endswith(suffix):
            return f"path ends with denied suffix {suffix!r}"
    for pat in DENY_PATH_PATTERNS:
        if pat.search(p):
            return f"path matches denied pattern {pat.pattern!r}"
    return None


def _truncate(text: str | None, n: int) -> str:
    if not text:
        return ""
    return text if len(text) <= n else text[-n:]


# ── Tool: file_picker ──────────────────────────────────────────────────────
@mcp.tool
def file_picker(
    prompt: str,
    max_results: int = 12,
    directories: list[str] | None = None,
) -> dict[str, Any]:
    """Find files relevant to a prompt. Uses ripgrep --files + filename heuristics."""
    if not prompt or not prompt.strip():
        return {"error": "prompt must be non-empty"}
    max_results = max(1, min(max_results, 50))
    # Default to /etc/nixos only. HOME_DIR is multi-GB and would be slow
    # to walk via ripgrep. Operators opt in either by setting
    # BUFFY_ALLOW_HOME_DIRS=1 or by passing explicit directories=[...] .
    allow_home = os.getenv("BUFFY_ALLOW_HOME_DIRS", "").lower() in ("1", "true", "yes")
    dirs = (
        directories
        if directories
        else ([NIXOS_DIR, HOME_DIR] if allow_home else [NIXOS_DIR])
    )

    safe_dirs = []
    for d in dirs:
        reason = _is_path_denied(d)
        if reason:
            continue
        if Path(d).is_dir():
            safe_dirs.append(d)
    if not safe_dirs:
        return {"error": "no accessible directories after safety check"}

    terms = [t for t in re.findall(r"[a-z0-9_./-]+", prompt.lower()) if len(t) >= 3][:8]
    if not terms:
        return {"results": [], "note": "prompt yielded no searchable terms"}

    results: list[dict[str, Any]] = []
    seen: set[str] = set()
    for d in safe_dirs:
        try:
            cp = subprocess.run(
                [
                    "rg", "--files", d,
                    "--type", "nix",
                    "--type", "py",
                    "--type", "md",
                    "--type-add", "yaml:*.{yaml,yml}",
                    "--type", "yaml",
                ],
                capture_output=True, text=True, timeout=SEARCH_TIMEOUT,
            )
            all_files = [f for f in cp.stdout.splitlines() if f]
        except subprocess.TimeoutExpired:
            continue
        except FileNotFoundError:
            return {"error": "ripgrep (rg) not installed"}

        for f in all_files:
            if any(t in f.lower() for t in terms):
                if f in seen:
                    continue
                seen.add(f)
                results.append({"path": f, "score": sum(1 for t in terms if t in f.lower())})

    results.sort(key=lambda r: -r["score"])
    final = results[:max_results]
    for r in final:
        try:
            with open(r["path"], "r", errors="replace") as fh:
                r["summary"] = " | ".join(
                    line.rstrip() for line in fh.readlines()[:3] if line.strip()
                )[:200]
        except OSError:
            r["summary"] = ""

    _audit("file_picker", {"prompt": prompt, "max_results": max_results, "dirs": dirs},
           f"{len(final)}/{len(results)} results")
    return {"query": prompt, "results": final, "total_candidates": len(results)}


# ── Tool: code_search ──────────────────────────────────────────────────────
@mcp.tool
def code_search(
    pattern: str,
    file_glob: str | None = None,
    cwd: str = NIXOS_DIR,
    max_results: int = 50,
) -> dict[str, Any]:
    """Search code via ripgrep. Returns {file, line, content} matches."""
    if not pattern or not pattern.strip():
        return {"error": "pattern must be non-empty"}
    if _is_path_denied(cwd):
        return {"error": f"cwd denied: {_is_path_denied(cwd)}"}
    max_results = max(1, min(max_results, 250))

    cmd = ["rg", "--line-number", "--no-heading", "--max-count", "2"]
    if file_glob:
        cmd += ["--glob", file_glob]
    cmd += [pattern, cwd]

    try:
        cp = subprocess.run(cmd, capture_output=True, text=True, timeout=SEARCH_TIMEOUT)
    except subprocess.TimeoutExpired:
        return {"error": f"search exceeded {SEARCH_TIMEOUT}s"}
    except FileNotFoundError:
        return {"error": "ripgrep (rg) not installed"}

    raw_lines = cp.stdout.splitlines()
    matches = []
    for line in raw_lines[:max_results]:
        parts = line.split(":", 2)
        if len(parts) >= 3:
            matches.append({"file": parts[0], "line": parts[1], "content": parts[2][:300]})

    _audit("code_search", {"pattern": pattern, "cwd": cwd, "glob": file_glob},
           f"{len(matches)} matches (rg_rc={cp.returncode})")
    return {
        "pattern": pattern,
        "count": len(matches),
        "matches": matches,
        "truncated": len(raw_lines) > max_results,
    }


# ── Tool: bash ─────────────────────────────────────────────────────────────
@mcp.tool
def bash(
    command: str,
    timeout: int = 120,
    cwd: str | None = None,
) -> dict[str, Any]:
    """Run a bash command. Catastrophic patterns blocked by deny-list."""
    if not command or not command.strip():
        return {"error": "command must be non-empty"}
    timeout = max(1, min(timeout, 1800))
    for pat in DENY_BASH_PATTERNS:
        if pat.search(command):
            return {"error": f"command matches denied pattern: {pat.pattern!r}"}
    if cwd and _is_path_denied(cwd):
        return {"error": f"cwd denied: {_is_path_denied(cwd)}"}

    try:
        cp = subprocess.run(
            command, shell=True, executable="/bin/bash",
            capture_output=True, text=True, timeout=timeout, cwd=cwd,
        )
    except subprocess.TimeoutExpired:
        _audit("bash", {"command": command, "timeout": timeout}, "TIMEOUT")
        return {"error": f"command exceeded {timeout}s", "command": command[:200]}

    _audit("bash", {"command": command, "timeout": timeout}, f"exit={cp.returncode}")
    return {
        "exit_code": cp.returncode,
        "stdout": _truncate(cp.stdout, 5000),
        "stderr": _truncate(cp.stderr, 5000),
        "command": command[:200],
    }


# ── Tool: read_files ───────────────────────────────────────────────────────
@mcp.tool
def read_files(
    paths: list[str],
    max_bytes_per_file: int = 50000,
) -> dict[str, Any]:
    """Read multiple files. Each bounded by max_bytes_per_file."""
    if not paths:
        return {"error": "paths must be non-empty"}
    if len(paths) > 20:
        return {"error": "max 20 files per call"}
    max_bytes_per_file = max(1, min(max_bytes_per_file, 500_000))

    files = []
    for p in paths:
        reason = _is_path_denied(p)
        if reason:
            files.append({"path": p, "error": f"denied: {reason}"})
            continue
        try:
            data = Path(p).read_bytes()[: max_bytes_per_file + 1]
            truncated = len(data) > max_bytes_per_file
            data = data[:max_bytes_per_file]
            content = data.decode("utf-8", errors="replace")
            files.append({"path": p, "content": content, "truncated": truncated, "bytes": len(data)})
        except OSError as e:
            files.append({"path": p, "error": str(e)})

    _audit("read_files", {"count": len(paths), "max_bytes": max_bytes_per_file},
           f"{sum(1 for f in files if 'content' in f)}/{len(paths)} ok")
    return {"files": files}


# ── Tool: write_file ───────────────────────────────────────────────────────
@mcp.tool
def write_file(
    path: str,
    content: str,
    mode: str = "0644",
) -> dict[str, Any]:
    """Write a file atomically. Path must not be on deny-list."""
    reason = _is_path_denied(path)
    if reason:
        return {"error": f"path denied: {reason}"}
    if not re.fullmatch(r"[0-7]{3,4}", mode):
        return {"error": f"mode must be 3-4 octal digits, got: {mode!r}"}

    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".buffy-tmp")
    try:
        tmp.write_text(content)
        tmp.chmod(int(mode, 8))
        # os.replace is the canonical atomic rename across POSIX (POSIX.1-2014
        # §rename). Path.replace falls back to copy+unlink on filesystems
        # where rename(2) cannot be atomic (e.g., some overlayfs / NFS).
        os.replace(tmp, target)
    except OSError as e:
        return {"error": f"write failed: {e}"}
    _audit("write_file", {"path": path, "mode": mode, "bytes": len(content)}, "ok")
    return {"path": path, "bytes": len(content), "mode": mode}


# ── Tool: tmux_run ─────────────────────────────────────────────────────────
@mcp.tool
def tmux_run(
    command: str,
    session: str = "buffy",
    timeout: int = 300,
) -> dict[str, Any]:
    """Run a command in a tmux session (interactive-friendly). Returns pane output."""
    if not command or not command.strip():
        return {"error": "command must be non-empty"}
    timeout = max(1, min(timeout, 1800))

    server = libtmux.Server()
    if not server.has_session(session):
        server.new_session(session, attach=False, window_name="buffy")
    sess = server.sessions.filter(session_name=session)[0]
    if sess.attached_window is None:
        sess.new_window(window_name="buffy")
    pane = sess.attached_window.attached_pane
    pane.send_keys(command, literal=False)

    elapsed = 0
    interval = 2
    output = ""
    while elapsed < timeout:
        time.sleep(interval)
        elapsed += interval
        output = "\n".join(pane.capture_pane())[-3000:]
        last = output.splitlines()[-1] if output else ""
        if PROMPT_RE.match(last.strip()):
            break

    _audit("tmux_run", {"command": command, "session": session, "timeout": timeout},
           f"elapsed={elapsed}s")
    return {"session": session, "elapsed_seconds": elapsed, "output": output}


# ── Tool: http_fetch ───────────────────────────────────────────────────────
@mcp.tool
def http_fetch(
    url: str,
    timeout: int = 30,
    headers: dict[str, str] | None = None,
    max_redirects: int = 5,
) -> dict[str, Any]:
    """GET a URL. LAN destinations by default (override via BUFFY_ALLOW_NON_LAN=1).
    Re-checks the LAN regex after each redirect to prevent a 302 chain
    from starting inside the cluster and landing on the public internet.
    """
    timeout = max(1, min(timeout, 120))
    max_redirects = max(0, min(max_redirects, 10))
    current = url
    hop = 0
    r = None
    while True:
        if not NETWORK_ALLOW_NON_LAN and not LAN_URL_RE.match(current or ""):
            return {"error": f"non-LAN URL blocked: {current!r}. Set BUFFY_ALLOW_NON_LAN=1 to override."}
        try:
            r = requests.get(current, timeout=timeout, headers=headers or {}, allow_redirects=False)
        except requests.RequestException as e:
            return {"error": f"request failed: {e}"}
        if r.is_redirect and hop < max_redirects:
            location = r.headers.get("Location", "")
            if not location:
                break
            current = requests.compat.urljoin(current, location)
            hop += 1
            continue
        break

    _audit("http_fetch", {"url": url, "final_url": current, "timeout": timeout, "redirects": hop},
           f"status={r.status_code} bytes={len(r.content)}")
    return {
        "url": url,
        "final_url": current,
        "redirects_followed": hop,
        "status": r.status_code,
        "content": r.text[:50000],
        "truncated": len(r.text) > 50000,
        "content_type": r.headers.get("content-type", ""),
    }


# ── Tool: web_search ───────────────────────────────────────────────────────
@mcp.tool
def web_search(
    query: str,
    count: int = 10,
    engines: list[str] | None = None,
) -> dict[str, Any]:
    """Web search via SearXNG JSON API. Returns {title, url, snippet} entries."""
    if not query or not query.strip():
        return {"error": "query must be non-empty"}
    count = max(1, min(count, 30))
    engines = engines or ["duckduckgo", "brave", "startpage"]

    if not NETWORK_ALLOW_NON_LAN and not LAN_URL_RE.match(SEARXNG_URL or ""):
        return {"error": f"searxng URL is non-LAN and BUFFY_ALLOW_NON_LAN is not set: {SEARXNG_URL!r}"}

    try:
        r = requests.get(
            f"{SEARXNG_URL.rstrip('/')}/search",
            params={"q": query, "format": "json", "engines": ",".join(engines)},
            timeout=15,
        )
    except requests.RequestException as e:
        return {"error": f"searxng unreachable: {e}"}
    if r.status_code != 200:
        return {"error": f"searxng HTTP {r.status_code}: {r.text[:200]}"}
    try:
        data = r.json()
    except ValueError as e:
        return {"error": f"searxng JSON decode: {e}"}
    results = [
        {
            "title": e.get("title", ""),
            "url": e.get("url", ""),
            "snippet": (e.get("content") or "")[:300],
        }
        for e in data.get("results", [])[:count]
    ]
    _audit("web_search", {"query": query, "count": count, "engines": engines},
           f"{len(results)} results")
    return {"query": query, "results": results, "engines": engines}


# ── Entry point ────────────────────────────────────────────────────────────
def main() -> None:
    import argparse
    p = argparse.ArgumentParser(description="Buffy MCP server")
    p.add_argument("--transport", choices=["stdio", "sse"], default="stdio")
    p.add_argument("--port", type=int, default=8765)
    args = p.parse_args()
    if args.transport == "sse":
        mcp.run(transport="sse", host="0.0.0.0", port=args.port)
    else:
        mcp.run()


if __name__ == "__main__":
    main()
