#!/usr/bin/env python3
"""
Try different message formats to see what Kryptex pools expect.
"""

import asyncio
import ssl
import json
import logging

logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)

async def test_format(name, messages):
    """Test a specific message format."""
    POOL_HOST = "xtm-c29-us.kryptex.network"
    POOL_PORT = 8040

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.set_ciphers('DEFAULT:@SECLEVEL=0')

    logger.info(f"\n{'='*60}\nTesting: {name}\n{'='*60}")

    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(POOL_HOST, POOL_PORT, ssl=context, server_hostname=POOL_HOST),
            timeout=15
        )

        ssl_obj = writer.get_extra_info('ssl_object')
        if ssl_obj:
            logger.info(f"TLS: {ssl_obj.version()}")

        for msg in messages:
            if isinstance(msg, str):
                msg_str = msg
            else:
                msg_str = json.dumps(msg, separators=(',', ':'))

            logger.info(f"Sending: {msg_str}")
            writer.write((msg_str + "\n").encode())
            await writer.drain()

            try:
                data = await asyncio.wait_for(reader.read(4096), timeout=3.0)
                if data:
                    logger.info(f"✓ RESPONSE: {data.decode('utf-8', errors='replace')}")
                else:
                    logger.info("No response")
            except asyncio.TimeoutError:
                logger.info("No response (timeout)")

        writer.close()
        await writer.wait_closed()

    except Exception as e:
        logger.error(f"Error: {e}")

async def main():
    WALLET = "krxXVNVMM7.zephyr-gpu"

    # Test 1: Just authorize first (no subscribe)
    await test_format("Authorize only (no subscribe)", [
        {"id": 1, "method": "mining.authorize", "params": [WALLET, "x"]}
    ])

    # Test 2: Subscribe with different agent string
    await test_format("Subscribe with cgminer agent", [
        {"id": 1, "method": "mining.subscribe", "params": ["cgminer/4.12.1", None]}
    ])

    # Test 3: Different order - authorize then subscribe
    await test_format("Authorize THEN subscribe", [
        {"id": 1, "method": "mining.authorize", "params": [WALLET, "x"]},
        {"id": 2, "method": "mining.subscribe", "params": ["lolMiner/1.98a", None]}
    ])

    # Test 4: Minimal login message (some pools use this)
    await test_format("Raw 'login' message", [
        {"login": WALLET, "pass": "x", "agent": "lolMiner/1.98a"}
    ])

    # Test 5: Try with Tari-specific params
    await test_format("Tari-style messages", [
        {"id": 1, "method": "login", "params": [WALLET, "x"]}
    ])

    # Test 6: Empty params
    await test_format("Subscribe with empty params", [
        {"id": 1, "method": "mining.subscribe", "params": []}
    ])

    # Test 7: Just wait after connection (maybe pool sends job first)
    await test_format("Just wait (no messages)", [])

    logger.info("\n" + "="*60)
    logger.info("All tests completed")
    logger.info("="*60)

if __name__ == "__main__":
    asyncio.run(main())
