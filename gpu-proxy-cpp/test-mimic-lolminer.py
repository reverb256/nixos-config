#!/usr/bin/env python3
"""
Mimic lolMiner exactly - same TLS config, same user agent, same message format.
"""

import asyncio
import ssl
import json
import logging

logging.basicConfig(
    level=logging.DEBUG,
    format='%(message)s'
)
logger = logging.getLogger(__name__)

POOL_HOST = "xtm-c29-us.kryptex.network"
POOL_PORT = 8040
WALLET = "krxXVNVMM7.zephyr-gpu"

async def test_exact_lolminer_behavior():
    """
    Test with exact lolMiner behavior.
    Key: lolMiner might send messages immediately after TLS handshake without waiting.
    """

    # Exact TLS configuration like lolMiner
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.maximum_version = ssl.TLSVersion.TLSv1_3

    logger.info(f"Connecting to {POOL_HOST}:{POOL_PORT} (TLS 1.2-1.3)")

    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(POOL_HOST, POOL_PORT, ssl=context, server_hostname=POOL_HOST),
            timeout=15
        )

        ssl_obj = writer.get_extra_info('ssl_object')
        if ssl_obj:
            logger.info(f"TLS Version: {ssl_obj.version()}")
            logger.info(f"Cipher: {ssl_obj.cipher()}")

        logger.info("Connected! Sending messages immediately (no waiting)...\n")

        # Send subscribe IMMEDIATELY after connection (like lolMiner might do)
        subscribe_msg = {
            "id": 1,
            "method": "mining.subscribe",
            "params": ["lolMiner/1.98a", None]
        }
        subscribe_str = json.dumps(subscribe_msg, separators=(',', ':'))
        logger.info(f"SENDING: {subscribe_str}")
        writer.write((subscribe_str + "\n").encode())
        await writer.drain()

        # Don't wait - send authorize immediately too
        authorize_msg = {
            "id": 2,
            "method": "mining.authorize",
            "params": [WALLET, "x"]
        }
        authorize_str = json.dumps(authorize_msg, separators=(',', ':'))
        logger.info(f"SENDING: {authorize_str}")
        writer.write((authorize_str + "\n").encode())
        await writer.drain()

        # Now wait for responses
        logger.info("\nWaiting for responses...")
        messages_received = 0
        for i in range(10):
            try:
                data = await asyncio.wait_for(reader.read(4096), timeout=1.0)
                if data:
                    messages_received += 1
                    text = data.decode('utf-8', errors='replace')
                    logger.info(f"[{messages_received}] RECEIVED: {repr(text)}")

                    # Try to parse as JSON
                    try:
                        obj = json.loads(text)
                        logger.info(f"    PARSED: {json.dumps(obj, indent=4)}")
                    except:
                        pass
                else:
                    logger.debug(f"[{i}] No data")
            except asyncio.TimeoutError:
                logger.debug(f"[{i}] No data (timeout)")

        logger.info(f"\nTotal messages received: {messages_received}")

        writer.close()
        await writer.wait_closed()

    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_exact_lolminer_behavior())
