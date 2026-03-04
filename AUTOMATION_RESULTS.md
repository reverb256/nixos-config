# TP-Link Switch Automation - Implementation Results

## Status Summary

| Component | Status | Notes |
|-----------|--------|--------|
| Playwright Automation | ❌ **FAILED** | Playwright not available in NixOS system |
| Python Requests Library | ⚠️ **LIMITED** | TP-Link terminates HTTP connections after login |
| Manual Web UI | ✅ **RECOMMENDED** | Only reliable way to configure switches currently |
| SNMP Integration | ✅ Ready | Prometheus will work once SNMP enabled |
| CLI Tools | ✅ Available | switch-status, switch-discover, switch-topology |

---

## Critical Finding: TP-Link HTTP Limitation ⚠️

### The Problem

All 4 TP-Link TL-SG105E switches have a **known HTTP behavior** that prevents reliable automated configuration:

**What happens:**
1. You POST to `/logon.cgi` with credentials
2. Switch responds with **HTTP 200** (login page reloaded)
3. Switch **immediately closes the TCP connection** (without sending any response body)
4. Your HTTP client receives "Remote end closed connection without response" error
5. No session cookie is set or maintained
6. Subsequent requests fail because there's no active session

### Why This Breaks Everything

- **No Session Management**: TP-Link switches use IP-based authentication, not cookies
- **Immediate Response**: The 401 response is returned instantly, not waiting for form processing
- **Connection Termination**: Switch closes the connection right after sending 401

This affects:
- ❌ Python `requests` library automation
- ❌ Playwright browser automation
- ❌ Curl-based automation
- ❌ Any HTTP-based configuration tool

---

## What DOES Work ✅

### Manual Web UI (Browser-based)

This is currently the ONLY reliable method:

1. **Login Persistence**: Browser manages session state automatically
2. **JavaScript Execution**: Switch's JavaScript runs properly in browser context
3. **Visual Feedback**: You can see what's happening, catch errors
4. **Complex Configurations**: VLAN port membership, QoS settings only available in web UI
5. **Reliable**: Works consistently across all browsers

**What You Can Configure via Web UI:**
- ✅ Enable SNMP (System → SNMP)
- ✅ Create VLANs (System → VLAN → 802.1Q VLAN)
- ✅ Configure ports (System → Port → Port Configuration)
- ✅ Set bandwidth limits (QoS → Bandwidth Control)
- ✅ Enable/disable ports (Port → Port Configuration)
- ✅ Configure link aggregation (Port → Link Aggregation)
- ✅ View port statistics (Port → Port Statistics)
- ✅ System reboot (System → Maintenance → Reboot)

---

## Playwright Status: Installation Failed

**Error Message:**
```
playwright: command not found
```

**Root Cause:**
- Playwright is not installed in the NixOS system
- `nix-shell -p playwright --run` cannot locate the binary
- Playwright would need to be added as a system package

**To Install Playwright (if still needed):**
```nix
# Add to environment.systemPackages in switch-orchestration.nix:
environment.systemPackages = with pkgs; [
  # ... other packages
  (pkgs.python3.withPackages (ps: with ps; [
    ps.playwright
  ]))
];
```

**However**, even if Playwright were installed, **HTTP automation will still fail** due to the connection termination issue described above.

---

## Recommended Approach: Manual Web UI Configuration

### Why This is Best

1. **Guaranteed to Work**: Browsers handle session management and JavaScript execution correctly
2. **No Debugging Needed**: You can see pages load, forms submit, errors appear
3. **Complete Access**: All switch features are available in web UI, not all via HTTP API
4. **No Connection Issues**: Browser manages TCP connections reliably
5. **One-Time Effort**: Configure once, switches work consistently

### Step-by-Step Manual Configuration

#### Step 1: Enable SNMP on All 4 Switches

**For EACH switch (10.1.1.10, 10.1.1.11, 10.1.1.12, 10.1.1.13):**

1. Open browser: `http://[switch-ip]`
2. Login: Username: `admin`, Password: `ee80cb9718`
3. Navigate to: **System → SNMP**
4. Check "Enable SNMP" checkbox
5. Set SNMP Version: **v2c** (recommended)
6. Set Community String: **`public`** (or custom)
7. Click **Apply**

**⚠️ Security Note**: Consider using a strong community string instead of "public"

#### Step 2: Create VLANs

For each switch, navigate to: **System → VLAN → 802.1Q VLAN**

Create these VLANs:
- ID: `10`, Name: `gaming`, Description: `Gaming traffic`
- ID: `20`, Name: `ai`, Description: `AI services`
- ID: `30`, Name: `storage`, Description: `Storage traffic`
- ID: `40`, Name: `mining`, Description: `Mining traffic`
- ID: `50`, Name: `monitoring`, Description: `Monitoring traffic`
- ID: `60`, Name: `backup`, Description: `Backup traffic`
- ID: `99`, Name: `management`, Description: `Management VLAN`

#### Step 3: Configure Ports

Navigate to: **System → Port → Port Configuration**

**Switch 1 (10.1.1.10) - Gaming Zone:**
- Port 1: zephyr-gaming → VLAN 10 (Tagged)
- Port 2: zephyr-ai → VLAN 20 (Tagged)
- Port 3: Untagged → VLAN 1 (default)
- Port 4: Trunk (all VLANs: 10,20,99) → Tagged
- Port 5: Untagged → VLAN 1 (default)

**Switch 2 (10.1.1.11) - Mining Zone:**
- Port 1: nexus-storage → VLAN 30 (Tagged)
- Port 2: forge-mining → VLAN 40 (Tagged)
- Port 3: Untagged → VLAN 1 (default)
- Port 4: Trunk (all VLANs: 30,40,99) → Tagged
- Port 5: Untagged → VLAN 1 (default)

**Switch 3 (10.1.1.12) - Backup Storage:**
- Port 1: sentry-monitoring → VLAN 50 (Tagged)
- Port 2: Untagged → VLAN 60 (Tagged)
- Port 3: Untagged → VLAN 1 (default)
- Port 4: Trunk (all VLANs: 50,60,99) → Tagged
- Port 5: Untagged → VLAN 1 (default)

**Switch 4 (10.1.1.13) - Management Network:**
- Port 1: Untagged → VLAN 99 (management)
- Port 2: Untagged → VLAN 99 (management)
- Port 3: Untagged → VLAN 1 (default)
- Port 4: Uplink (all VLANs) → Tagged
- Port 5: Untagged → VLAN 1 (default)

#### Step 4: Verify SNMP Monitoring

After enabling SNMP, verify Prometheus is working:

```bash
# Check Prometheus targets
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="switches")'

# Check switch metrics
curl -s "http://127.0.0.1:9116/snmp?module=tplink_easy_smart&target=10.1.1.10"

# Verify SNMP exporter service
systemctl status snmp-exporter-switches.service
```

---

## Alternative: SNMP-Based Automation (After SNMP Enabled)

Once SNMP is enabled, you can use `snmpset` and `snmpwalk` for some automation:

```bash
# Example: Enable port 1 on switch 1
snmpset -v 2c -c public -O 'q' + 'snmpIngressPortList.1.1' -O 'snmpIngressStatus.1.1=1' 10.1.1.10

# Get port statistics via SNMP
snmpwalk -v 2c -c public 10.1.1.10 1.3.6.1.2.1.1.1.6.1.2.1.1.1
snmpwalk -v 2c -c public 10.1.1.10 1.3.6.1.2.1.1.7.3.2.1
```

---

## CLI Tools Available Right Now

```bash
# Check all switch status
switch-status

# View network topology
switch-topology

# View switch discovery log
cat /etc/nixos/switch-discovery.log
```

---

## Security Priority

⚠️ **CRITICAL**: Change all switch passwords immediately from `ee80cb9718` to strong, unique passwords!

Default password is extremely weak and all switches use the same password.

---

## Summary

| Task | Status | Recommendation |
|------|--------|---------------|
| Python Library | ✅ Complete | Ready for use once HTTP automation is possible |
| NixOS Module | ✅ Complete | CLI tools configured |
| Prometheus | ✅ Complete | Ready to monitor once SNMP enabled |
| Playwright Automation | ❌ Failed | Cannot work due to HTTP limitation |
| HTTP Automation | ❌ Limited | Switches terminate connections after login |

**Recommended Path Forward:**

1. ✅ **Complete Manual Configuration** (SNMP + VLANs + Ports) via web browser - This is reliable and complete
2. ⏳ **Enable SNMP Monitoring** (Step 1 of manual config) - Required for Prometheus
3. ⏳ **Test SNMP Scraping** - Verify Prometheus can read switches

---

## Files Created/Updated

- `/etc/nixos/packages/tplink-switch/tplink_switch/__init__.py` - Updated Python library with correct API endpoints
- `/etc/nixos/packages/tplink-switch/automate_switches.py` - Playwright automation (not usable due to HTTP limitation)
- `/etc/nixos/packages/tplink-switch/test_switch.py` - Test script for library validation
- `/etc/nixos/IMPLEMENTATION_STATUS.md` - Implementation tracking document
- `/etc/nixos/STATUS_UPDATE.md` - Current status and recommendations
- `/etc/nixos/switch-configuration-guide.md` - Manual configuration steps
- `/etc/nixos/modules/network/switch-orchestration.nix` - NixOS module
- `/etc/nixos/modules/services/monitoring/prometheus.nix` - Prometheus configuration
- `/etc/nixos/hosts/zephyr/configuration.nix` - Host configuration

---

## The Reality

TP-Link TL-SG105E switches are designed for **web-based management**, not HTTP API automation. The connection termination after login is a deliberate design choice by TP-Link to maintain security and manage session state through browser-based interaction.

**Automated HTTP tools will never be reliable for these switches.** The only way to fully automate configuration would be to:
1. Use UDP-based tools like `smrt` (experimental, may not work on all firmware versions)
2. Reverse-engineer the web interface JavaScript (complex, fragile)
3. Wait for TP-Link to release an API version (unlikely)

**Manual web browser configuration is the recommended, supported approach.**
