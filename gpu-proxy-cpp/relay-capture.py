#!/usr/bin/env python3
"""
Simple relay to capture traffic between lolminer and Kryptex.
Listen on port 3333, forward to pool, log everything.
"""

import asyncio
import ssl
import logging

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(message)s')
logger = logging.getLogger(__name__)

POOL_HOST = "xtm-c29-us.kryptex.network"
POOL_PORT = 8040
RELAY_PORT = 3333

class RelayConnection:
    def __init__(self, reader, writer, name, peer=None):
        self.reader = reader
        self.writer = writer
        self.name = name
        self.peer = peer
        self.byte_count = 0

    async def forward_loop(self):
        """Forward data from this side to peer."""
        while True:
            try:
                data = await self.reader.read(4096)
                if not data:
                    logger.info(f"[{self.name}] Connection closed (transferred {self.byte_count} bytes)")
                    break

                self.byte_count += len(data)

                # Log the data
                try:
                    text = data.decode('utf-8', errors='replace')
                    logger.info(f"[{self.name}] {len(data)} bytes: {repr(text[:500])}")
                except:
                    logger.info(f"[{self.name}] {len(data)} bytes binary")

                # Forward to peer
                if self.peer and self.peer.writer:
                    try:
                        self.peer.writer.write(data)
                        await self.peer.writer.drain()
                    except Exception as e:
                        logger.error(f"[{self.name}] Forward error: {e}")
                        break
            except Exception as e:
                logger.error(f"[{self.name}] Read error: {e}")
                break

        if self.peer:
            self.peer.peer = None

async def handle_client(client_reader, client_writer, pool_reader, pool_writer):
    """Handle a client (lolminer) connection."""
    client = RelayConnection(client_reader, client_writer, "CLIENT")
    pool = RelayConnection(pool_reader, pool_writer, "POOL", client)
    client.peer = pool

    # Run both forwarding loops
    await asyncio.gather(
        client.forward_loop(),
        pool.forward_loop(),
        return_exceptions=True
    )

async def main():
    # Connect to pool first
    logger.info(f"Connecting to pool {POOL_HOST}:{POOL_PORT}")

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    pool_reader, pool_writer = await asyncio.open_connection(
        POOL_HOST, POOL_PORT,
        ssl=context,
        server_hostname=POOL_HOST
    )

    logger.info(f"Connected to pool! Waiting for client on port {RELAY_PORT}")
    logger.info(f"Configure lolminer: --pool localhost:{RELAY_PORT} --user krxXVNVMM7.zephyr-gpu --pass x --tls on")

    # Start server for client
    async def handle_client_wrapper(r, w):
        await handle_client(r, w, pool_reader, pool_writer)

    server = await asyncio.start_server(handle_client_wrapper, '0.0.0.0', RELAY_PORT)
    await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Shutting down...")
