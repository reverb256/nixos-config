#!/usr/bin/env python3
"""Stratum auth translator proxy.

Translates peakminer's named-params authorize to standard array-form
so the pool sees "WALLET.WORKER" as the login string.

Usage: stratum-auth-translator.py <poolHost> <poolPort> <listenPort> <workerName>

Listens on 127.0.0.1:<listenPort>, forwards to <poolHost>:<poolPort>,
and intercepts mining.authorize to convert named params -> array form.
"""

import asyncio
import json
import sys


class StratumProxy:
    def __init__(self, pool_host: str, pool_port: int, worker_name: str):
        self.pool_host = pool_host
        self.pool_port = pool_port
        self.worker_name = worker_name

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            pool_reader, pool_writer = await asyncio.open_connection(self.pool_host, self.pool_port)
        except Exception as e:
            print(f"[proxy] Failed to connect to pool {self.pool_host}:{self.pool_port}: {e}")
            writer.close()
            return

        async def forward(src: asyncio.StreamReader, dst: asyncio.StreamWriter, direction: str):
            try:
                while True:
                    line = await asyncio.wait_for(src.readline(), timeout=300)
                    if not line:
                        break
                    decoded = line.decode("utf-8", errors="replace").strip()
                    if not decoded:
                        continue

                    # Intercept mining.authorize from miner -> pool
                    if direction == "up" and '"mining.authorize"' in decoded or '"mining.authorize"' in decoded:
                        try:
                            msg = json.loads(decoded)
                            if isinstance(msg, dict):
                                method = msg.get("method", "")
                                if method == "mining.authorize":
                                    params = msg.get("params", {})
                                    if isinstance(params, dict):
                                        # Extract wallet from login field
                                        login = params.get("login", "")
                                        password = params.get("pass", "")
                                        # Reformat as standard array
                                        msg["params"] = [login, password]
                                        decoded = json.dumps(msg)
                            elif isinstance(msg, list) and len(msg) >= 2:
                                method = msg[1] if len(msg) > 1 else ""
                                if "mining.authorize" in str(method):
                                    # Already array form, but inject worker name if missing
                                    params = msg[2] if len(msg) > 2 else []
                                    if isinstance(params, list) and len(params) >= 1:
                                        login = params[0]
                                        if login and "." not in login:
                                            params[0] = f"{login}.{self.worker_name}"
                                            msg[2] = params
                                            decoded = json.dumps(msg)
                        except json.JSONDecodeError:
                            pass

                    dst.write((decoded + "\n").encode("utf-8"))
                    await dst.drain()
            except (asyncio.TimeoutError, ConnectionError, OSError):
                pass
            finally:
                try:
                    dst.close()
                except Exception:
                    pass

        await asyncio.gather(
            forward(reader, pool_writer, "up"),
            forward(pool_reader, writer, "down"),
        )

    async def start(self, listen_port: int):
        server = await asyncio.start_server(self.handle_client, "127.0.0.1", listen_port)
        print(f"[proxy] Listening on 127.0.0.1:{listen_port}, forwarding to {self.pool_host}:{self.pool_port}")
        async with server:
            await server.serve_forever()


def main():
    if len(sys.argv) != 5:
        print(f"Usage: {sys.argv[0]} <poolHost> <poolPort> <listenPort> <workerName>", file=sys.stderr)
        sys.exit(1)

    pool_host = sys.argv[1]
    pool_port = int(sys.argv[2])
    listen_port = int(sys.argv[3])
    worker_name = sys.argv[4]

    proxy = StratumProxy(pool_host, pool_port, worker_name)
    asyncio.run(proxy.start(listen_port))


if __name__ == "__main__":
    main()
