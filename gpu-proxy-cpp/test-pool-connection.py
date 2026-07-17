#!/usr/bin/env python3
"""
Connect to Kryptex pool and log all messages to understand the protocol.
"""

import asyncio
import ssl
import json
import logging
import os

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

POOL_HOST = "xtm-c29-us.kryptex.network"
POOL_PORT = 8040

# Wallet from lolminer config
WALLET = "krxXVNVMM7.zephyr-gpu"

async def test_connection():
    """Test connection to pool and log all messages."""

    # Create SSL context
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.maximum_version = ssl.TLSVersion.TLSv1_3
    context.set_ciphers('DEFAULT:@SECLEVEL=0')

    logger.info(f"Connecting to {POOL_HOST}:{POOL_PORT}")

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

        ssl_obj = writer.get_extra_info('ssl_object')
        if ssl_obj:
            logger.info(f"TLS version: {ssl_obj.version()}")
            logger.info(f"Cipher: {ssl_obj.cipher()}")

        logger.info("Connected! Waiting for initial data from pool...")

        # First, wait a bit to see if pool sends anything without us sending anything
        try:
            data = await asyncio.wait_for(reader.read(4096), timeout=3.0)
            if data:
                logger.info(f"Received BEFORE subscribe: {data.decode('utf-8', errors='replace')}")
            else:
                logger.info("No data received before subscribe")
        except asyncio.TimeoutError:
            logger.info("No data from pool before subscribe (timeout)")

        # Now send subscribe (like lolminer would)
        subscribe_msg = {
            "id": 1,
            "method": "mining.subscribe",
            "params": ["lolMiner/1.98a", None]
        }
        subscribe_str = json.dumps(subscribe_msg, separators=(',', ':'))
        logger.info(f"Sending subscribe: {subscribe_str}")
        writer.write((subscribe_str + "\n").encode())
        await writer.drain()

        # Wait for response
        try:
            data = await asyncio.wait_for(reader.read(4096), timeout=5.0)
            if data:
                response = data.decode('utf-8', errors='replace')
                logger.info(f"Received AFTER subscribe: {response}")

                # Try to parse as JSON
                try:
                    obj = json.loads(response)
                    logger.info(f"Parsed JSON: {json.dumps(obj, indent=2)}")
                except:
                    pass
            else:
                logger.info("No response to subscribe")
        except asyncio.TimeoutError:
            logger.info("No response to subscribe (timeout)")

        # Try sending authorize (maybe that's what Kryptex expects first?)
        authorize_msg = {
            "id": 2,
            "method": "mining.authorize",
            "params": [WALLET, "x"]
        }
        authorize_str = json.dumps(authorize_msg, separators=(',', ':'))
        logger.info(f"Sending authorize: {authorize_str}")
        writer.write((authorize_str + "\n").encode())
        await writer.drain()

        # Wait for response
        try:
            data = await asyncio.wait_for(reader.read(4096), timeout=5.0)
            if data:
                response = data.decode('utf-8', errors='replace')
                logger.info(f"Received AFTER authorize: {response}")
                try:
                    obj = json.loads(response)
                    logger.info(f"Parsed JSON: {json.dumps(obj, indent=2)}")
                except:
                    pass
            else:
                logger.info("No response to authorize")
        except asyncio.TimeoutError:
            logger.info("No response to authorize (timeout)")

        # Keep reading for a few more seconds to catch any delayed responses
        logger.info("Keeping connection open for 5 more seconds...")
        for i in range(5):
            try:
                data = await asyncio.wait_for(reader.read(4096), timeout=1.0)
                if data:
                    logger.info(f"Delayed data [{i}]: {data.decode('utf-8', errors='replace')}")
                else:
                    logger.debug(f"No data [{i}]")
            except asyncio.TimeoutError:
                logger.debug(f"No data [{i}] (timeout)")

        writer.close()
        await writer.wait_closed()

    except Exception as e:
        logger.error(f"Connection error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_connection())
