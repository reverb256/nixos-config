#!/usr/bin/env python3
"""
Stratum auth-format translation proxy.

Sits between PeakMiner and a Stratum V1 pool, rewriting the authorize
payload from PeakMiner's non-standard named-params format to the standard
array format used by most pools.
"""

import json
import socket
import threading
import argparse


class LineBuffer:
    """Reads from a socket and yields complete lines.

    TCP is a stream, not message-oriented.  A single recv() can contain
    multiple JSON lines or a partial line.  This buffers until we have
    a complete newline-terminated message before yielding.
    """
    def __init__(self, sock: socket.socket):
        self.sock = sock
        self.buf = b""

    def lines(self):
        while True:
            # If we already have a complete line, yield it without reading
            if b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                yield line.decode("utf-8", errors="replace").strip()
                continue

            # Need more data
            try:
                data = self.sock.recv(4096)
            except Exception:
                data = b""
            if not data:
                # Connection closed — flush any remaining data
                remaining = self.buf
                self.buf = b""
                if remaining:
                    yield remaining.decode("utf-8", errors="replace").strip()
                return
            self.buf += data


def normalize_payload(payload: dict, wallet: str, worker: str) -> dict:
    """Convert named-params authorize to array form with proper wallet.worker."""
    if payload.get("method") == "mining.authorize":
        params = payload.get("params")
        if isinstance(params, dict):
            # Named-params format from peakminer (without --legacy-auth)
            # Override with explicit wallet.worker so pool always sees the name
            payload["params"] = [f"{wallet}.{worker}", "x"]
        elif isinstance(params, list) and len(params) >= 1:
            # Already array — still re-write with our wallet.worker so
            # it's deterministic regardless of what the miner sends
            password = params[1] if len(params) > 1 else "x"
            payload["params"] = [f"{wallet}.{worker}", password]
    return payload


def forward_data(src: socket.socket, dst: socket.socket,
                 name: str, wallet: str, worker: str):
    """Read lines from src, translate auth, write to dst."""
    buf = LineBuffer(src)
    try:
        for line_str in buf.lines():
            if not line_str:
                continue
            if line_str.startswith("{"):
                try:
                    payload = json.loads(line_str)
                    normalized = normalize_payload(payload, wallet, worker)
                    dst.sendall((json.dumps(normalized) + "\n").encode("utf-8"))
                except json.JSONDecodeError:
                    dst.sendall((line_str + "\n").encode("utf-8"))
            else:
                dst.sendall((line_str + "\n").encode("utf-8"))
    except Exception:
        pass
    finally:
        try:
            src.shutdown(socket.SHUT_RDWR)
        except Exception:
            pass


def handle_client(client_socket: socket.socket, client_address,
                  target_host: str, target_port: int,
                  wallet: str, worker: str):
    try:
        pool_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        pool_socket.connect((target_host, target_port))

        client_th = threading.Thread(
            target=forward_data,
            args=(client_socket, pool_socket, "\u2192pool", wallet, worker))
        pool_th = threading.Thread(
            target=forward_data,
            args=(pool_socket, client_socket, "\u2190pool", wallet, worker))

        client_th.start()
        pool_th.start()

        client_th.join()
        pool_th.join()
    except Exception as e:
        print(f"Error handling client {client_address}: {e}")
    finally:
        try:
            client_socket.close()
        except Exception:
            pass


def parse_args():
    parser = argparse.ArgumentParser(
        description="Stratum auth-translator proxy")
    parser.add_argument("--listen-host", default="0.0.0.0")
    parser.add_argument("--listen-port", type=int, default=21540)
    parser.add_argument("--target", default="prl.kryptex.network:7048")
    parser.add_argument("--wallet", default="")
    parser.add_argument("--worker", default="")
    return parser.parse_args()


def main():
    args = parse_args()

    target = args.target
    if ":" in target:
        target_host, target_port = target.rsplit(":", 1)
        target_port = int(target_port)
    else:
        target_host = target
        target_port = 7048

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.listen_host, args.listen_port))
    server.listen(5)

    print(f"Stratum auth-translator proxy listening on "
          f"{args.listen_host}:{args.listen_port}")
    print(f"Forwarding to pool: {target_host}:{target_port}")
    print(f"Wallet: {args.wallet}, Worker: {args.worker}")
    print("Press Ctrl+C to stop")

    try:
        while True:
            client_socket, client_address = server.accept()
            print(f"New connection from {client_address}")
            t = threading.Thread(
                target=handle_client,
                args=(client_socket, client_address,
                      target_host, target_port,
                      args.wallet, args.worker))
            t.daemon = True
            t.start()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        server.close()


if __name__ == "__main__":
    main()
