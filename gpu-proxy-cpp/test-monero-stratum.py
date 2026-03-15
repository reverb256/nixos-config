#!/usr/bin/env python3
"""
Test Monero-style Stratum protocol with Kryptex pool.
XMRig uses Monero Stratum, NOT Bitcoin Stratum!

Monero protocol messages:
- login (not mining.subscribe)
- job (not mining.notify)
- submit (different format)
"""

import asyncio
import ssl
import json
import logging

logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)

POOL_HOST = "xtm-c29-us.kryptex.network"
POOL_PORT = 8040
WALLET = "krxXVNVMM7.zephyr-gpu"

async def test_monero_stratum():
    """Test Monero-style Stratum protocol."""

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    logger.info(f"Connecting to {POOL_HOST}:{POOL_PORT}")

    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(POOL_HOST, POOL_PORT, ssl=context, server_hostname=POOL_HOST),
            timeout=15
        )

        ssl_obj = writer.get_extra_info('ssl_object')
        if ssl_obj:
            logger.info(f"TLS: {ssl_obj.version()}")

        logger.info("Connected!\n")

        # Test 1: Monero-style "login" message
        logger.info("=" * 60)
        logger.info("TEST 1: Monero-style 'login' message")
        logger.info("=" * 60)

        # Monero stratum login format
        login_msg = {
            "method": "login",
            "params": {
                "login": WALLET,
                "pass": "x",
                "agent": "XMRig/6.25.0"
            },
            "id": 1
        }

        login_str = json.dumps(login_msg, separators=(',', ':'))
        logger.info(f"SENDING: {login_str}")
        writer.write((login_str + "\n").encode())
        await writer.drain()

        # Wait for response
        try:
            data = await asyncio.wait_for(reader.read(4096), timeout=5.0)
            if data:
                response = data.decode('utf-8', errors='replace')
                logger.info(f"RESPONSE: {repr(response)}")
                try:
                    obj = json.loads(response)
                    logger.info(f"PARSED: {json.dumps(obj, indent=2)}")

                    # Check for "job" key - Monero pools send jobs immediately after login
                    if "job" in obj or "result" in obj:
                        logger.info("SUCCESS: Pool responded to Monero-style login!")
                except:
                    pass
            else:
                logger.info("No response")
        except asyncio.TimeoutError:
            logger.info("No response (timeout)")

        # Test 2: Alternative Monero login format
        logger.info("\n" + "=" * 60)
        logger.info("TEST 2: Alternative Monero login format")
        logger.info("=" * 60)

        login_msg2 = {
            "id": 1,
            "jsonrpc": "2.0",
            "method": "login",
            "params": [WALLET, "x"]
        }

        login_str2 = json.dumps(login_msg2, separators=(',', ':'))
        logger.info(f"SENDING: {login_str2}")
        writer.write((login_str2 + "\n").encode())
        await writer.drain()

        try:
            data = await asyncio.wait_for(reader.read(4096), timeout=5.0)
            if data:
                response = data.decode('utf-8', errors='replace')
                logger.info(f"RESPONSE: {repr(response)}")
        except asyncio.TimeoutError:
            logger.info("No response (timeout)")

        # Test 3: Get height (some Monero pools support this)
        logger.info("\n" + "=" * 60)
        logger.info("TEST 3: getheight (Monero daemon command)")
        logger.info("=" * 60)

        height_msg = {"id": 2, "method": "getheight"}
        height_str = json.dumps(height_msg, separators=(',', ':'))
        logger.info(f"SENDING: {height_str}")
        writer.write((height_str + "\n").encode())
        await writer.drain()

        try:
            data = await asyncio.wait_for(reader.read(4096), timeout=5.0)
            if data:
                response = data.decode('utf-8', errors='replace')
                logger.info(f"RESPONSE: {repr(response)}")
        except asyncio.TimeoutError:
            logger.info("No response (timeout)")

        writer.close()
        await writer.wait_closed()

    except Exception as e:
        logger.error(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_monero_stratum())
