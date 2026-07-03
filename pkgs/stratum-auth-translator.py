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


def normalize_payload(payload: dict) -> dict:
    if payload.get("method") in {"mining.authorize", "mining.subscribe"}:
        if isinstance(payload.get("params"), dict):
            params = payload["params"]
            payload["params"] = [params.get("login", ""), params.get("pass", "x")]
    return payload


def forward_data(src: socket.socket, dst: socket.socket, name: str):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            try:
                decoded = data.decode("utf-8").strip()
                if decoded.startswith("{"):
                    payload = json.loads(decoded)
                    normalized = normalize_payload(payload)
                    dst.sendall((json.dumps(normalized) + "\n").encode("utf-8"))
                else:
                    dst.sendall(data)
            except (json.JSONDecodeError, UnicodeDecodeError):
                dst.sendall(data)
    except Exception:
        pass
    finally:
        try:
            src.shutdown(socket.SHUT_RDWR)
        except Exception:
            pass


def handle_client(client_socket: socket.socket, client_address, target_host: str, target_port: int):
    try:
        pool_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        pool_socket.connect((target_host, target_port))

        client_thread = threading.Thread(target=forward_data, args=(client_socket, pool_socket, "→pool"))
        pool_thread = threading.Thread(target=forward_data, args=(pool_socket, client_socket, "←pool"))

        client_thread.start()
        pool_thread.start()

        client_thread.join()
        pool_thread.join()
    except Exception as e:
        print(f"Error handling client {client_address}: {e}")
    finally:
        try:
            client_socket.close()
        except Exception:
            pass


def parse_args():
    parser = argparse.ArgumentParser(description="Stratum auth-translator proxy")
    parser.add_argument("--listen-host", default="0.0.0.0")
    parser.add_argument("--listen-port", type=int, default=21540)
    parser.add_argument("--target", default="prl.kryptex.network:7048")
    parser.add_argument("--wallet", default=None)
    parser.add_argument("--worker", default=None)
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

    print(f"Stratum auth-translator proxy listening on {args.listen_host}:{args.listen_port}")
    print(f"Forwarding to pool: {target_host}:{target_port}")
    print("Press Ctrl+C to stop")

    try:
        while True:
            client_socket, client_address = server.accept()
            print(f"New connection from {client_address}")
            client_thread = threading.Thread(
                target=handle_client, args=(client_socket, client_address, target_host, target_port)
            )
            client_thread.daemon = True
            client_thread.start()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        server.close()


if __name__ == "__main__":
    main()
