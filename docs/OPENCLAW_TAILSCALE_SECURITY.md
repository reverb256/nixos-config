# OpenClaw Tailscale Security Configuration

## Overview
OpenClaw is now secured behind Tailscale VPN, protecting against CVE-2026-25253 (1-Click RCE vulnerability).

## Configuration Changes

### 1. Bind Address (Host Configuration)
**File:** `hosts/zephyr/configuration.nix`
- Changed from: `gatewayBind = "0.0.0.0"` (all interfaces, including public internet)
- Changed to: `gatewayBind = "100.81.182.5"` (Tailscale interface only)

### 2. Firewall Rules
**File:** `hosts/zephyr/configuration.nix`
- OpenClaw port 18789/18790 now ONLY accessible via Tailscale interface
- Blocks all public internet access
- Only Tailscale-connected devices can reach OpenClaw

### 3. OpenClaw Module
**File:** `modules/openclaw.nix`
- Added `bindAddress` option for configurable listen address
- Updated systemd service to use `--host` parameter

## Access Instructions

### From Other Tailscale Devices:
```bash
# Access OpenClaw from any device on your Tailscale network
curl http://100.81.182.5:18789/health
```

### Testing Connection:
```bash
# From local machine
tailscale ping zephyr
# Should show direct connection via Tailscale

# Test OpenClaw access
curl http://100.81.182.5:18789/health
```

## Security Benefits

1. **CVE-2026-25253 Protection**: Blocks 1-click RCE attacks from malicious links
2. **Zero Public Exposure**: No ports open to internet
3. **Encrypted Traffic**: All OpenClaw traffic encrypted via WireGuard
4. **Access Control**: Only authenticated Tailscale users can access

## Verification

### Check OpenClaw is Listening on Tailscale IP:
```bash
sudo ss -tlnp | grep 18789
# Should show: 100.81.182.5:18789

# Should NOT show: 0.0.0.0:18789 or :::18789
```

### Verify No Public Exposure:
```bash
# From external server (should fail)
curl --connect-timeout 5 http://YOUR_PUBLIC_IP:18789/health
# Should timeout or connection refused

# From Tailscale device (should succeed)
curl http://100.81.182.5:18789/health
# Should return {"status":"ok"}
```

## Troubleshooting

### If OpenClaw Not Accessible:
1. Check Tailscale is running: `tailscale status`
2. Verify Tailscale IP: `tailscale ip -4`
3. Check OpenClaw service: `systemctl status openclaw-container-declarative`
4. Check firewall: `sudo iptables -L | grep 18789`

### If Tailscale IP Changed:
1. Get new IP: `tailscale ip -4`
2. Update `hosts/zephyr/configuration.nix`: `gatewayBind = "NEW_IP";`
3. Rebuild: `sudo nixos-rebuild switch --flake .#zephyr`

## References
- CVE-2026-25253: https://socradar.io/blog/cve-2026-25253-rce-openclaw-auth-token/
- Tailscale Security: https://tailscale.com/kb/1196/security-hardening
- OpenClaw RCE Details: https://thehackernews.com/2026/02/openclaw-bug-enables-one-click-remote.html
