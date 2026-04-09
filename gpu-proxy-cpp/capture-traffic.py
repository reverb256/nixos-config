#!/usr/bin/env python3
"""
Simple Stratum proxy to capture and log all messages between lolminer and Kryptex.
This helps us understand the actual protocol being used.
"""

import asyncio
import ssl
import socket
import json
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

POOL_HOST = "xtm-c29-us.kryptex.network"
POOL_PORT = 8040
PROXY_PORT = 3336

class StratumProxy:
    def __init__(self, reader, writer, name):
        self.reader = reader
        self.writer = writer
        self.name = name
        self.peer = None

    async def send_line(self, line: str):
        """Send a line to the peer."""
        if self.writer:
            try:
                self.writer.write((line + "\n").encode())
                await self.writer.drain()
                logger.info(f"[{self.name}] SENT: {line}")
            except Exception as e:
                logger.error(f"[{self.name}] Send error: {e}")
                self.peer = None

    async def receive_loop(self):
        """Receive messages and forward to peer."""
        buffer = ""
        while True:
            try:
                data = await self.reader.read(4096)
                if not data:
                    logger.info(f"[{self.name}] Connection closed")
                    break

                text = data.decode('utf-8', errors='replace')
                buffer += text

                # Process complete lines
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    line = line.strip()
                    if line:
                        logger.info(f"[{self.name}] RECV: {line}")

                        # Forward to peer
                        if self.peer and self.peer.writer:
                            try:
                                self.peer.writer.write((line + "\n").encode())
                                await self.peer.writer.drain()
                            except Exception as e:
                                logger.error(f"[{self.name}] Forward error: {e}")
                                self.peer = None
                                break
            except Exception as e:
                logger.error(f"[{self.name}] Receive error: {e}")
                break

        logger.info(f"[{self.name}] Exiting receive loop")
        if self.peer:
            self.peer.peer = None

async def handle_miner(miner_reader, miner_writer, pool_connection):
    """Handle a miner connection."""
    logger.info("Miner connected")

    miner = StratumProxy(miner_reader, miner_writer, "MINER")
    miner.peer = pool_connection
    pool_connection.peer = miner

    # Start receiving from miner
    await miner.receive_loop()

async def connect_to_pool():
    """Connect to the mining pool."""
    logger.info(f"Connecting to pool {POOL_HOST}:{POOL_PORT}")

    # Create SSL context (match lolminer settings)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.maximum_version = ssl.TLSVersion.TLSv1_3
    context.set_ciphers('DEFAULT:@SECLEVEL=0')

    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(
                POOL_HOST,
                POOL_PORT,
                ssl=context,
                server_hostname=POOL_HOST
            ),
            timeout=30
        )
        logger.info(f"Connected to pool")
        return StratumProxy(reader, writer, "POOL")
    except Exception as e:
        logger.error(f"Failed to connect to pool: {e}")
        return None

async def main():
    pool_conn = await connect_to_pool()
    if not pool_conn:
        logger.error("Could not connect to pool")
        return

    # Start listening for miners
    server = await asyncio.start_server(
        lambda r, w: handle_miner(r, w, pool_conn),
        '0.0.0.0',
        PROXY_PORT
    )

    logger.info(f"Proxy listening on port {PROXY_PORT}")
    logger.info("Configure lolminer to use localhost:3336 instead of the pool")

    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Shutting down...")
