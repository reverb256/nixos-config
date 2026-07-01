#!/usr/bin/env python3
"""
Stratum auth-format translation proxy.

Sits between PeakMiner and a Stratum V1 pool, rewriting the authorize
payload from PeakMiner's non-standard named-params format to the standard
array format used by most pools.

PeakMiner sends:
    {"id": 1, "method": "mining.authorize", "params": {"login": "user", "pass": "x"}}

Pools expect:
    {"id": 1, "method": "mining.authorize", "params": ["user", "x"]}

This proxy runs locally and forwards to the pool with the correct format.
"""

import sys
import socket
import threading
import json
import time
from typing import Optional, Tuple

# Configuration
PROXY_HOST = "0.0.0.0"
PROXY_PORT = 21540  # PeakMiner connects here
POOL_HOST = "prl.kryptex.network"
POOL_PORT = 7048

# Mapping of PeakMiner wallet → worker name
WALLET_MAP = {
    "krxXVNVMM7": {
        "zephyr-3060ti": "krxXVNVMM7.zephyr-3060ti",
        "zephyr-3090": "krxXVNVMM7.zephyr-3090",
        "forge-4060-0": "krxXVNVMM7.forge-4060-0",
        "forge-4060-1": "krxXVNVMM7.forge-4060-1",
        "nexus-3060ti": "krxXVNVMM7.nexus-3060ti",
    }
}

def normalize_payload(payload: dict) -> dict:
    """Convert PeakMiner named-params to array format."""
    if "method" in payload and payload["method"] in [
        "mining.authorize",
        "mining.subscribe",
    ]:
        if isinstance(payload["params"], dict):
            # Convert {"login": "user", "pass": "x"} → ["user", "x"]
            params = payload["params"]
            payload["params"] = [params.get("login", ""), params.get("pass", "x")]

    return payload

def forward_data(src: socket.socket, dst: socket.socket, name: str):
    """Forward data between sockets."""
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break

            # Try to parse and modify JSON
            try:
                decoded = data.decode('utf-8').strip()
                if decoded.startswith("{"):
                    payload = json.loads(decoded)
                    normalized = normalize_payload(payload)
                    modified = json.dumps(normalized) + "\n"
                    dst.sendall(modified.encode('utf-8'))
                    # print(f"[{name}] Modified: {decoded[:50]}... → {modified[:50]}...")
                else:
                    dst.sendall(data)
            except (json.JSONDecodeError, UnicodeDecodeError):
                # Not JSON, forward as-is
                dst.sendall(data)
    except Exception as e:
        pass
    finally:
        try:
            src.shutdown(socket.SHUT_RDWR)
        except:
            pass

def handle_client(client_socket: socket.socket, client_address: Tuple[str, int]):
    """Handle incoming PeakMiner connection."""
    try:
        # Connect to pool
        pool_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        pool_socket.connect((POOL_HOST, POOL_PORT))

        # Start forwarding threads
        client_thread = threading.Thread(
            target=forward_data, args=(client_socket, pool_socket, "→pool")
        )
        pool_thread = threading.Thread(
            target=forward_data, args=(pool_socket, client_socket, "←pool")
        )

        client_thread.start()
        pool_thread.start()

        client_thread.join()
        pool_thread.join()
    except Exception as e:
        print(f"Error handling client {client_address}: {e}")
    finally:
        try:
            client_socket.close()
        except:
            pass

def main():
    """Start the proxy server."""
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((PROXY_HOST, PROXY_PORT))
    server.listen(5)

    print(f"Stratum auth-translator proxy listening on {PROXY_HOST}:{PROXY_PORT}")
    print(f"Forwarding to pool: {POOL_HOST}:{POOL_PORT}")
    print("Press Ctrl+C to stop")

    try:
        while True:
            client_socket, client_address = server.accept()
            print(f"New connection from {client_address}")
            client_thread = threading.Thread(
                target=handle_client, args=(client_socket, client_address)
            )
            client_thread.daemon = True
            client_thread.start()
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        server.close()

if __name__ == "__main__":
    main()