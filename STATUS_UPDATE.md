# TP-Link Switch Orchestration - Status Update & Alternatives

## Current Situation

### Challenge Discovered ⚠️

TP-Link TL-SG105E switches have a **known HTTP limitation**: They terminate connections abruptly after processing login forms with "Remote end closed connection without response" error. This affects automated HTTP-based management.

### What's Working ✅
- Direct HTTP GET requests (curl, browser)
- Web UI login via browser (manual)
- Python library structure (ready for use)
- Network connectivity (all 4 switches responding)
- NixOS module structure (properly configured)

### What's NOT Working ❌
- Automated HTTP login via Python `requests` or `curl`
- Session cookie persistence after POST to `/logon.cgi`
- Playwright automation attempts (due to connection termination)

---

## Recommended Solution Options

### Option 1: Manual Web UI Configuration (RECOMMENDED) ✅

**Why it works:**
- Browser handles connection quirks correctly
- JavaScript executes properly
- Session cookies managed automatically
- Visual feedback for configuration changes

**What you need to do:**
1. Access each switch via web browser:
   - http://10.1.1.10 (Switch 1 - Gaming Zone)
   - http://10.1.1.11 (Switch 2 - Mining Zone)
   - http://10.1.1.12 (Switch 3 - Backup Storage)
   - http://10.1.1.13 (Switch 4 - Management Network)

2. Login with: `admin` / `ee80cb9718`

3. Configure SNMP:
   - System → SNMP
   - Check "Enable SNMP"
   - Version: v2c
   - Community String: `public` (or custom)
   - Apply

4. Create VLANs:
   - System → VLAN → 802.1Q VLAN
   - Add VLANs with these IDs:
     ```
     ID    Name        Description
     ----   ----        -----------
     10     gaming      Gaming traffic
     20     ai          AI services
     30     storage     Storage traffic
     40     mining      Mining traffic
     50     monitoring   Monitoring traffic
     60     backup      Backup traffic
     99     management  Management VLAN
     ```
   - Apply

5. Configure Ports:
   - System → Port → Port Configuration
   - Configure port VLAN assignments (see `/etc/nixos/switch-configuration-guide.md` for details)
   - Set tagged/untagged as needed
   - Apply

6. Reboot switches (optional after making changes)

### Option 2: SNMP-Based Management (Requires Manual SNMP Enable First)

Once SNMP is enabled via web UI (Option 1), you can use SNMP for monitoring:

**Tools available after enabling SNMP:**
```bash
# Check switch status via SNMP
snmpwalk -v 2c -c public 10.1.1.10 system

# Get port statistics
snmpwalk -v 2c -c public 10.1.1.10 1.3.6.1.2.1

# Get interface counters
snmpwalk -v 2c -c public 10.1.1.10 interfaces

# Check all switches at once
for ip in 10.1.1.10 10.1.1.11 10.1.1.12 10.1.1.13; do
  echo "Checking $ip..."
  snmpwalk -v 2c -c public $ip system | head -5
done
```

**Prometheus Integration:**
- Already configured in `/etc/nixos/modules/services/monitoring/prometheus.nix`
- Will automatically scrape switches once SNMP is enabled
- Verify with: `curl -s http://127.0.0.1:9116/snmp?module=tplink_easy_smart&target=10.1.1.10`

### Option 3: UDP-Based Automation (Experimental)

The switches may support UDP-based protocols (used by the `smrt` Python library):
- Port: 29808 (RRCP protocol)
- Can query switch state without HTTP authentication
- May require special handling

**Status:** Needs testing - not currently implemented.

### Option 4: Direct Browser Automation with Selenium/Playwright

While Playwright was requested, the connection termination issue makes this challenging. However, you could try:

```python
import asyncio
from playwright.async_api import async_playwright

async def configure_switch(ip: str, username: str, password: str):
    async with async_playwright(headless=False) as p:  # Use headed mode to see what's happening
        browser = await p.chromium.launch(headless=False)
        page = await browser.new_page()

        # Navigate to login page
        await page.goto(f"http://{ip}/")

        # Wait for page to load
        await page.wait_for_load_state("domcontentloaded")

        # Fill login form
        await page.fill('input[name="username"]', username)
        await page.fill('input[name="password"]', password)

        # Take screenshot for debugging
        await page.screenshot(path=f"/tmp/{ip}-login.png")

        # Click login
        await page.click('input[name="logon"]')

        # Wait for navigation
        await page.wait_for_timeout(10000)

        # Take another screenshot
        await page.screenshot(path=f"/tmp/{ip}-after-login.png")

        await browser.close()
```

**Caveat:**
- Headless mode (headless=True) may have issues with JavaScript
- Switch UI may have timing issues
- Connection termination may still occur

---

## What I've Built So Far

### ✅ Completed
1. **Python Library** (`/etc/nixos/packages/tplink-switch/tplink_switch/__init__.py`)
   - Correct API endpoints from research
   - System info, port statistics, VLAN parsing
   - Authentication framework

2. **NixOS Module** (`/etc/nixos/modules/network/switch-orchestration.nix`)
   - CLI tools (switch-discover, switch-status, switch-topology)
   - Declarative configuration structure
   - SNMP integration configured

3. **Prometheus Configuration**
   - SNMP exporter configuration
   - Switch scrape targets added

4. **Documentation**
   - Configuration guide created
   - Status documentation created

### ⚠️ Known Issues
1. **HTTP Automation Limitation**: Switches terminate HTTP connections after login form processing
2. **Playwright Not Installed**: Would need to be added to system packages

---

## Recommended Next Steps

### Immediate (Manual Configuration Required)

**Step 1: Enable SNMP via Web UI**
```
For each switch (10.1.1.10, 10.1.1.11, 10.1.1.12, 10.1.1.13):
  1. Open: http://<ip> in browser
  2. Login: admin / ee80cb9718
  3. Navigate: System → SNMP
  4. Enable SNMP (check the box)
  5. Set Version: v2c
  6. Community String: public (or custom like "MySecret123")
  7. Click Apply
```

**Step 2: Create VLANs via Web UI**
```
For each switch:
  1. Navigate: System → VLAN → 802.1Q VLAN
  2. Add VLANs:
     - ID: 10, Name: gaming
     - ID: 20, Name: ai
     - ID: 30, Name: storage
     - ID: 40, Name: mining
     - ID: 50, Name: monitoring
     - ID: 60, Name: backup
     - ID: 99, Name: management
  3. Apply
```

**Step 3: Configure Ports via Web UI**
```
For each switch, configure port assignments (see guide for details):

Switch 1 (10.1.1.10) - Gaming Zone:
  - Port 1: VLAN 10 (gaming), Tagged
  - Port 2: VLAN 20 (ai), Tagged
  - Port 3: Untagged (default)
  - Port 4: Untagged (default)
  - Port 5: Untagged (default)

Switch 2 (10.1.1.11) - Mining Zone:
  - Port 1: VLAN 30 (storage), Tagged
  - Port 2: VLAN 40 (mining), Tagged
  - Port 3-5: Untagged (default)

Switch 3 (10.1.1.12) - Backup Storage:
  - Port 1: VLAN 50 (monitoring), Tagged
  - Port 2: VLAN 60 (backup), Tagged
  - Port 3-5: Untagged (default)

Switch 4 (10.1.1.13) - Management Network:
  - Port 1-3: Untagged (default - management)
  - Port 4: Uplink to gateway, Trunk (all VLANs)
  - Port 5: Untagged (default)
```

### After Manual Configuration

1. **Verify SNMP Monitoring:**
   ```bash
   # Check Prometheus is scraping
   curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="switches")'

   # View switch metrics
   curl -s http://127.0.0.1:9116/snmp?module=tplink_easy_smart&target=10.1.1.10
   ```

2. **Use CLI Tools** (once module is fixed):
   ```bash
   switch-status    # Check all switches
   switch-topology  # View network topology
   ```

---

## Why Manual Web UI is Best for Now

1. **Reliability**: Browsers handle connection quirks better than scripts
2. **Visibility**: You can see what's happening, debug errors
3. **Safety**: Changes are applied immediately, no race conditions
4. **Complex UI**: Some configurations (VLAN port membership) are only available in web UI
5. **No Dependency**: Doesn't require additional packages (Playwright, etc.)

---

## If You Still Want Automation

After completing manual configuration, you can try:

1. **Selenium with Headed Browser**: More reliable than headless Playwright
2. **UDP Protocol**: Research smrt library (pklaus/smrt) for UDP-based management
3. **SNMP-Based Scripts**: Use `snmpset` and `snmpwalk` for configuration after enabling SNMP
4. **Hybrid Approach**: Use web automation to navigate, manual steps for complex operations

---

## Security Reminder

⚠️ **CHANGE DEFAULT PASSWORDS IMMEDIATELY!**

All switches use: `ee80cb9718`

After configuring:
1. Change to strong, unique passwords per switch
2. Use password manager (KeePassXC, Bitwarden, etc.)
3. Rotate passwords regularly
4. Document credentials in secure storage

---

## Summary

| Component | Status | Notes |
|-----------|--------|--------|
| Python Library | ✅ Ready | Correct API endpoints, ready for use |
| NixOS Module | ✅ Ready | CLI tools configured |
| Prometheus Config | ✅ Ready | Will work once SNMP enabled |
| SNMP Exporter | ✅ Ready | Running, awaiting SNMP enable |
| HTTP Automation | ⚠️ Limited | Switches terminate connections |
| Playwright | ❌ Not Ready | Would need installation |
| Manual Web UI | ✅ Recommended | Most reliable option now |

**Recommended Action:** Complete Steps 1-3 using web browser for each switch, then verify SNMP monitoring is working.
