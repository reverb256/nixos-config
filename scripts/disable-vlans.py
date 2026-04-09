#!/usr/bin/env python3
"""Disable VLANs on all TP-Link switches"""
import asyncio
from playwright.async_api import async_playwright

SWITCHES = ["10.1.1.10", "10.1.1.11", "10.1.1.12", "10.1.1.13"]

async def disable_vlan(ip):
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()

        try:
            await page.goto(f"http://{ip}", timeout=10000)
            await page.fill('input[name="username"]', 'admin')
            await page.fill('input[name="password"]', 'ee80cb9718')
            await page.click('input[name="logon"]')
            await asyncio.sleep(2)

            await page.goto(f"http://{ip}/VlanMtuRpm.htm", timeout=10000)
            await asyncio.sleep(2)

            # Try to find and uncheck VLAN enable checkbox
            checkbox = await page.query_selector('input[type="checkbox"]')
            if checkbox:
                is_checked = await checkbox.is_checked()
                print(f"{ip}: VLAN checkbox is checked: {is_checked}")
                if is_checked:
                    await checkbox.uncheck()
                    await asyncio.sleep(1)
                    # Click Apply button
                    btn = await page.query_selector('input[value="Apply"]')
                    if btn:
                        await btn.click()
                        await asyncio.sleep(2)
                        print(f"{ip}: ✅ VLAN DISABLED")
                    else:
                        print(f"{ip}: ! No Apply button found")
                else:
                    print(f"{ip}: ✓ VLAN was not enabled")
            else:
                print(f"{ip}: ! No VLAN checkbox found")

        except Exception as e:
            print(f"{ip}: ERROR - {e}")

        await browser.close()

async def main():
    for ip in SWITCHES:
        await disable_vlan(ip)
        await asyncio.sleep(1)

    print("\n=== DONE ===")

asyncio.run(main())
