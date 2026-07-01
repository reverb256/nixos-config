#!/usr/bin/env python3
"""
Stratum auth-format translation proxy.

Sits between PeakMiner and a Stratum V1 pool, rewriting the authorize
payload from PeakMiner's non-standard named-params format to the standard
array-form that pools use for worker identification.

Named-params IN (from peakminer):
  {"method":"mining.authorize","params":{"wallet":"WALLET","worker":"WORKER",...}}

Array-form OUT (to pool):
  {"method":"mining.authorize","params":["WALLET.WORKER","x"]}

This makes the pool see "WALLET.WORKER" as the login string, so the
dashboard displays per-worker names — while peakminer's share submission
path (which only works on named-params) continues to function normally.

Usage:
  python3 stratum-auth-translator.py <pool_host> <pool_port> <listen_port> <worker_name>

Then point peakminer at:
  --url stratum+tcp://127.0.0.1:<listen_port> --user WALLET --worker <worker_name>
"""
import socket
import json
import threading
import sys


def process_message(line: bytes, direction: str, worker_override: str | None = None) -> bytes:
    """Parse, optionally rewrite, and return a Stratum JSON-RPC line."""
    stripped = line.strip()
    if not stripped:
        return line

    try:
        msg = json.loads(stripped)
    except json.JSONDecodeError:
        return line

    # Only rewrite client→pool messages (authorize)
    if direction != "C->P":
        return line

    method = msg.get("method", "")
    params = msg.get("params", {})

    # Rewrite named-params authorize to array-form
    if method == "mining.authorize" and isinstance(params, dict):
        wallet = params.get("wallet", "")
        worker = worker_override or params.get("worker", "")
        agent = params.get("agent", "")
        password = params.get("password", "x")

        # Build array-form: ["wallet.worker", "password"]
        if worker:
            login = f"{wallet}.{worker}"
        else:
            login = wallet

        new_params = [login, password]
        msg["params"] = new_params

        rewritten = json.dumps(msg) + "\n"
        print(f"  [TRANSLATE] {wallet}.{worker} → array-form login='{login}'", flush=True)
        return rewritten.encode()

    return line


def forward(src, dst, label, worker_override=None):
    """Forward data between sockets, rewriting authorize payloads."""
    buf = b""
    while True:
        try:
            data = src.recv(65536)
            if not data:
                break
            buf += data
            # Process complete lines
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                processed = process_message(line + b"\n", label, worker_override)
                dst.sendall(processed)
            # Forward any remaining partial data
            if buf:
                dst.sendall(buf)
                buf = b""
        except (ConnectionResetError, BrokenPipeError, OSError):
            break


def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <pool_host> <pool_port> <listen_port> [worker_name]")
        print()
        print("  pool_host    Upstream pool hostname (e.g. prl.kryptex.network)")
        print("  pool_port    Upstream pool port (e.g. 7048)")
        print("  listen_port  Local port to listen on")
        print("  worker_name  Optional: override worker name in all authorize calls")
        print()
        print("Point peakminer at: --url stratum+tcp://127.0.0.1:<listen_port>")
        print("Peakminer will use named-params (shares work), proxy rewrites to array-form")
        print("Pool sees WALLET.WORKER login → dashboard shows per-worker names")
        sys.exit(1)

    pool_host = sys.argv[1]
    pool_port = int(sys.argv[2])
    listen_port = int(sys.argv[3])
    worker_override = sys.argv[4] if len(sys.argv) > 4 else None

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", listen_port))
    srv.listen(5)
    print(f"Stratum auth translator listening on 0.0.0.0:{listen_port}", flush=True)
    print(f"  Upstream: {pool_host}:{pool_port}", flush=True)
    print(f"  Worker override: {worker_override or '(use peakminer --worker)'}", flush=True)
    print(f"  Translation: named-params → array-form", flush=True)
    print(flush=True)

    while True:
        try:
            client, addr = srv.accept()
            print(f"[+] Miner connected from {addr}", flush=True)

            pool = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            pool.connect((pool_host, pool_port))
            print(f"[+] Connected to pool {pool_host}:{pool_port}", flush=True)

            t1 = threading.Thread(
                target=forward,
                args=(client, pool, "C->P", worker_override),
                daemon=True,
            )
            t2 = threading.Thread(
                target=forward,
                args=(pool, client, "P->C", None),
                daemon=True,
            )
            t1.start()
            t2.start()

            # Wait for threads to finish (connection closed)
            t1.join()
            t2.join()
            print(f"[-] Connection from {addr} closed", flush=True)

        except (ConnectionResetError, BrokenPipeError, OSError) as e:
            print(f"[!] Error: {e}", flush=True)
            continue
        except KeyboardInterrupt:
            print("\n[*] Shutting down", flush=True)
            break

    srv.close()


if __name__ == "__main__":
    main()
