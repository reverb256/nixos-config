#!/usr/bin/env python3
"""
Enhanced relay with better debugging to understand why lolMiner can't connect.
Listen on plain TCP, forward to TLS pool.
"""

import asyncio
import ssl
import logging
import socket

logging.basicConfig(
    level=logging.DEBUG,
    format='[%(asctime)s] %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

POOL_HOST = "xtm-c29-us.kryptex.network"
POOL_PORT = 8040
RELAY_PORT = 3339  # Use a different port

class RelayConnection:
    def __init__(self, reader, writer, name, peer=None):
        self.reader = reader
        self.writer = writer
        self.name = name
        self.peer = peer
        self.byte_count = 0

    async def forward_loop(self):
        """Forward data from this side to peer."""
        logger.info(f"[{self.name}] Starting forward loop")
        try:
            while True:
                data = await self.reader.read(8192)
                if not data:
                    logger.info(f"[{self.name}] Connection closed (transferred {self.byte_count} bytes)")
                    break

                self.byte_count += len(data)

                # Try to decode as text for logging
                try:
                    text = data.decode('utf-8', errors='replace')
                    logger.info(f"[{self.name} -> {self.peer.name if self.peer else 'NONE'}] {len(data)}b: {repr(text[:200])}")
                except:
                    logger.info(f"[{self.name} -> {self.peer.name if self.peer else 'NONE'}] {len(data)}b binary data")

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
        finally:
            if self.peer:
                self.peer.peer = None
            try:
                self.writer.close()
                await self.writer.wait_closed()
            except:
                pass

async def handle_client(client_reader, client_writer, pool_reader, pool_writer):
    """Handle a client (lolminer) connection."""
    # Get client address for logging
    addr = client_writer.get_extra_info('peername')
    logger.info(f"Client connected from {addr}!")

    client = RelayConnection(client_reader, client_writer, "CLIENT")
    pool = RelayConnection(pool_reader, pool_writer, "POOL", client)
    client.peer = pool

    # Run both forwarding loops
    await asyncio.gather(
        client.forward_loop(),
        pool.forward_loop(),
        return_exceptions=True
    )

    logger.info("Handler done")

async def connect_to_pool():
    """Connect to the pool with TLS."""
    logger.info(f"Connecting to pool {POOL_HOST}:{POOL_PORT}")

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_2

    try:
        pool_reader, pool_writer = await asyncio.wait_for(
            asyncio.open_connection(
                POOL_HOST,
                POOL_PORT,
                ssl=context,
                server_hostname=POOL_HOST
            ),
            timeout=15
        )

        ssl_obj = pool_writer.get_extra_info('ssl_object')
        if ssl_obj:
            logger.info(f"Pool TLS: {ssl_obj.version()}")

        logger.info(f"Connected to pool!")
        return pool_reader, pool_writer
    except Exception as e:
        logger.error(f"Failed to connect to pool: {e}")
        return None, None

async def main():
    # Pre-connect to pool
    pool_reader, pool_writer = await connect_to_pool()
    if not pool_reader or not pool_writer:
        logger.error("Could not connect to pool")
        return

    # Start server for client (PLAIN TCP - no TLS on client side)
    logger.info(f"Starting relay server on port {RELAY_PORT}")
    logger.info(f"Configure lolminer: --pool localhost:{RELAY_PORT} --user krxXVNVMM7.zephyr-gpu --pass x --tls off")

    async def handle_client_wrapper(r, w):
        # For each new client, we need a fresh pool connection
        pr, pw = await connect_to_pool()
        if pr and pw:
            await handle_client(r, w, pr, pw)
        else:
            w.close()
            await w.wait_closed()

    # Close the initial pool connection
    pool_writer.close()
    await pool_writer.wait_closed()

    server = await asyncio.start_server(handle_client_wrapper, '0.0.0.0', RELAY_PORT)

    # Get the actual socket address
    addr = server.sockets[0].getsockname()
    logger.info(f"Relay listening on {addr}")

    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Shutting down...")
