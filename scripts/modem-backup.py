#!/usr/bin/env python3
"""
Rogers Modem (Hitron CODA-4582) Control and Backup
Access modem at 10.1.1.1 to configure and backup settings
"""

import asyncio
import json
from datetime import datetime
from pathlib import Path
from playwright.async_api import async_playwright

MODEM_IP = "10.1.1.1"
MODEM_URL = f"http://{MODEM_IP}"
USERNAME = "admin"
PASSWORD = "ee80cb9718"

BACKUP_DIR = Path("/tmp/modem-backup")
BACKUP_DIR.mkdir(parents=True, exist_ok=True)


async def main():
    print("="*60)
    print("Rogers Modem Control & Backup")
    print("="*60)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False)
        page = await browser.new_page()

        try:
            # Login
            print(f"\nLogging in to {MODEM_URL}...")
            await page.goto(MODEM_URL, timeout=15000)
            await asyncio.sleep(2)

            # Fill login form
            await page.fill('input[name="username"]', USERNAME)
            await page.fill('input[name="password"]', PASSWORD)
            await page.click('input[type="submit"]')
            await asyncio.sleep(5)

            current_url = page.url
            print(f"  Current URL: {current_url}")

            if "check.jst" in current_url or "Login" in await page.title():
                print(f"  ✗ Login failed")
                await browser.close()
                return

            print(f"  ✓ Logged in")

            # Capture key pages
            pages_to_visit = [
                ("at_a_glance", f"{MODEM_URL}/at_a_glance.jst"),
                ("connected_devices", f"{MODEM_URL}/connected_devices_computers.jst"),
                ("local_network", f"{MODEM_URL}/local_ip_configuration.jst"),
                ("wifi", f"{MODEM_URL}/wireless_network_configuration.jst"),
                ("status", f"{MODEM_URL}/connection_status.jst"),
                ("firewall_ipv4", f"{MODEM_URL}/firewall_settings_ipv4.jst"),
                ("lan", f"{MODEM_URL}/lan.jst"),
            ]

            backup_data = {
                "timestamp": datetime.now().isoformat(),
                "pages": {}
            }

            for page_name, page_url in pages_to_visit:
                try:
                    print(f"  Visiting: {page_name}")
                    await page.goto(page_url, timeout=15000)
                    await asyncio.sleep(3)

                    # Screenshot
                    screenshot_path = BACKUP_DIR / f"modem-{page_name}.png"
                    await page.screenshot(path=str(screenshot_path))

                    # Get text content
                    text = await page.evaluate("() => document.body.innerText")

                    # Save HTML
                    html = await page.evaluate("() => document.body.innerHTML")
                    html_path = BACKUP_DIR / f"modem-{page_name}.html"
                    html_path.write_text(html, encoding='utf-8')

                    backup_data["pages"][page_name] = {
                        "url": page_url,
                        "screenshot": str(screenshot_path),
                        "html_file": str(html_path),
                    }

                    print(f"    ✓ Saved: {screenshot_path.name}")

                except Exception as e:
                    print(f"    ✗ Error: {e}")

            # Save backup JSON
            json_path = BACKUP_DIR / "modem-backup.json"
            json_path.write_text(json.dumps(backup_data, indent=2))
            print(f"\n  ✓ Backup saved: {json_path}")

            # Keep browser open for manual control
            print(f"\n{'='*60}")
            print(f"Browser open at: {current_url}")
            print(f"Press Ctrl+C to close...")
            print(f"{'='*60}")

            # Wait indefinitely for manual interaction
            await asyncio.sleep(float('inf'))

        except Exception as e:
            print(f"  ✗ Error: {e}")
            import traceback
            traceback.print_exc()

        await browser.close()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nClosed.")
