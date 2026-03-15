#!/usr/bin/env python3
"""
Test: Connect to pool, DON'T send anything, just wait and see what it sends.
"""

import asyncio
import ssl
import logging

logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)

POOL_HOST = "xtm-c29-us.kryptex.network"
POOL_PORT = 8040

async def test_pool_sends_first():
    """Connect and wait - see if pool sends anything without us sending first."""

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.maximum_version = ssl.TLSVersion.TLSv1_3

    logger.info(f"Connecting to {POOL_HOST}:{POOL_PORT}...")

    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(POOL_HOST, POOL_PORT, ssl=context, server_hostname=POOL_HOST),
            timeout=15
        )

        ssl_obj = writer.get_extra_info('ssl_object')
        if ssl_obj:
            logger.info(f"TLS: {ssl_obj.version()}, Cipher: {ssl_obj.cipher()}")

        logger.info("Connected! Waiting 10 seconds to see what pool sends...")

        # Just wait - don't send ANYTHING
        messages_received = []
        for i in range(10):
            try:
                data = await asyncio.wait_for(reader.read(4096), timeout=1.0)
                if data:
                    text = data.decode('utf-8', errors='replace')
                    messages_received.append(text)
                    logger.info(f"[{i}] POOL SENT: {repr(text[:200])}")
                else:
                    logger.debug(f"[{i}] No data")
            except asyncio.TimeoutError:
                logger.debug(f"[{i}] No data (timeout)")

        logger.info(f"\nTotal messages received: {len(messages_received)}")
        for i, msg in enumerate(messages_received):
            logger.info(f"\n--- Message {i+1} ---\n{msg}\n")

        writer.close()
        await writer.wait_closed()

    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_pool_sends_first())
