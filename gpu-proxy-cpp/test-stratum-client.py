#!/usr/bin/env python3
"""
Act as a Stratum client and send proper messages to the pool.
This mimics what lolMiner would do.
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

async def send_and_wait(reader, writer, msg, timeout=5.0):
    """Send a message and wait for response."""
    msg_str = json.dumps(msg, separators=(',', ':'))
    logger.info(f"SENDING: {msg_str}")

    writer.write((msg_str + "\n").encode())
    await writer.drain()

    try:
        data = await asyncio.wait_for(reader.read(4096), timeout=timeout)
        if data:
            response = data.decode('utf-8', errors='replace')
            logger.info(f"RECEIVED: {repr(response)}")

            # Try to parse as JSON
            try:
                obj = json.loads(response)
                logger.info(f"PARSED: {json.dumps(obj, indent=2)}")
                return obj
            except:
                return response
        else:
            logger.info("No response (connection closed)")
            return None
    except asyncio.TimeoutError:
        logger.info("No response (timeout)")
        return None

async def test_stratum_protocol():
    """Test the Stratum protocol with Kryptex pool."""

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_2

    logger.info(f"Connecting to {POOL_HOST}:{POOL_PORT}")

    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(POOL_HOST, POOL_PORT, ssl=context, server_hostname=POOL_HOST),
            timeout=15
        )

        ssl_obj = writer.get_extra_info('ssl_object')
        if ssl_obj:
            logger.info(f"TLS: {ssl_obj.version()}")

        logger.info("Connected! Testing protocol...\n")

        # Test 1: Standard Stratum subscribe
        logger.info("=" * 60)
        logger.info("TEST 1: mining.subscribe")
        logger.info("=" * 60)
        result = await send_and_wait(reader, writer, {
            "id": 1,
            "method": "mining.subscribe",
            "params": ["lolMiner/1.98a", None]
        })
        if result:
            logger.info(f"Result: {result}")

        # Test 2: Authorize
        logger.info("\n" + "=" * 60)
        logger.info("TEST 2: mining.authorize")
        logger.info("=" * 60)
        result = await send_and_wait(reader, writer, {
            "id": 2,
            "method": "mining.authorize",
            "params": [WALLET, "x"]
        })
        if result:
            logger.info(f"Result: {result}")

        # Test 3: Try configure (some pools expect this)
        logger.info("\n" + "=" * 60)
        logger.info("TEST 3: mining.configure")
        logger.info("=" * 60)
        result = await send_and_wait(reader, writer, {
            "id": 3,
            "method": "mining.configure",
            "params": []
        })
        if result:
            logger.info(f"Result: {result}")

        # Test 4: Just wait for more data
        logger.info("\n" + "=" * 60)
        logger.info("TEST 4: Waiting 5 seconds for unsolicited messages")
        logger.info("=" * 60)
        for i in range(5):
            try:
                data = await asyncio.wait_for(reader.read(4096), timeout=1.0)
                if data:
                    text = data.decode('utf-8', errors='replace')
                    logger.info(f"Unsolicited message: {repr(text)}")
            except asyncio.TimeoutError:
                pass

        writer.close()
        await writer.wait_closed()

    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_stratum_protocol())
