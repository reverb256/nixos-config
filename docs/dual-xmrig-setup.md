# Dual XMRig Setup - GameMode Integration

**Created:** 2026-03-14
**Status:** ✅ Configuration Complete - Pending Secret Encryption

## Overview

Two XMRig instances provide flexible mining during gaming:
- **Always-on instance**: Mines continuously (4-6 threads) - never pauses
- **Flexible instance**: Extra capacity when idle (8-12 threads) - pauses during gaming

## Thread Allocation

| Host | Total Cores | Always-on | Flexible | Idle Total | Gaming Total |
|------|-----------|-----------|----------|------------|--------------|
| Zephyr | 32 | 4 (12%) | 12 (38%) | 16 (50%) | 4 (12%) |
| Nexus | 24 | 4 (17%) | 8 (33%) | 12 (50%) | 4 (17%) |
| Sentry | 16 | 4 (25%) | 4 (25%) | 8 (50%) | 4 (25%) |

## Services

| Instance | Service Name | API Port | Token File | Status |
|----------|--------------|----------|------------|--------|
| Always-on | `xmrig-always.service` | 8081 | `/run/agenix/xmrig-always-api-token` | Never pauses |
| Flexible | `xmrig-flexible.service` | 8082 | `/run/agenix/xmrig-flexible-api-token` | Pauses on gaming |

## GameMode Integration

When a game starts:
1. GameMode activates (gamemoded starts)
2. GameMode `custom.start` hook runs:
   - Pauses `xmrig-flexible` service
   - Sends notification: "Mining paused - Flexible XMRig instance paused during gaming"
   - Logs to `/var/log/gamemode-mining.log`

When game ends:
1. GameMode deactivates
2. GameMode `custom.end` hook runs:
   - Starts `xmrig-flexible` service
   - Sends notification: "Mining resumed - Flexible XMRig instance resumed"
   - Logs to `/var/log/gamemode-mining.log`

## Control Commands

```bash
# Check status of both instances
xmrig-api-control status always    # Always-on instance
xmrig-api-control status flexible  # Flexible instance

# Manual pause/resume (per instance)
xmrig-api-control pause always
xmrig-api-control resume flexible

# Set thread count (per instance)
xmrig-api-control threads 8 always
xmrig-api-control threads 12 flexible

# Systemd control (alternative)
systemctl status xmrig-always
systemctl status xmrig-flexible
systemctl stop xmrig-flexible    # Manually pause
systemctl start xmrig-flexible   # Manually resume
```

## Files Modified

1. **`modules/mining/dual-xmrig.nix`** (NEW)
   - Dual XMRig module with always-on and flexible instances
   - Host-aware thread allocation defaults
   - Separate API ports and token files per instance

2. **`modules/gaming/gaming.nix`**
   - Updated GameMode hooks to control flexible instance
   - Added pause/resume logic and notifications

3. **`modules/system/xmrig-api-control.nix`**
   - Updated to support multi-instance control
   - New syntax: `xmrig-api-control <command> [instance]`

4. **`modules/default.nix`**
   - Added `dual-xmrig.nix` to module imports

5. **`hosts/zephyr/configuration.nix`**
   - Switched from single `xmrig` to `xmrigDual`
   - Added two new API token secrets

6. **`hosts/nexus/configuration.nix`**
   - Switched from single `xmrig` to `xmrigDual`
   - Added `inputs` to function arguments
   - Added `age` secrets section

## Secret Files (PENDING ENCRYPTION)

The following secret files need to be encrypted with agenix:

```bash
# Generate and encrypt tokens
cd /etc/nixos

# For zephyr (local deployment - use agenix directly)
agenix -e secrets/xmrig-always-api-token.age
agenix -e secrets/xmrig-flexible-api-token.age

# Copy the same tokens to nexus deployment
# Or generate separate ones for each host
```

**Temporary placeholder contents:**
- `secrets/xmrig-always-api-token.age`: `GGD70gZPrRv7hqdgax7RVpugyV0Fe6kR` (unencrypted!)
- `secrets/xmrig-flexible-api-token.age`: `CRivJIGnnX0AuUTnQw4RNXlVYfC6QGbU` (unencrypted!)

## Deployment Steps

1. **Encrypt the API tokens** (required before deployment):
   ```bash
   cd /etc/nixos
   agenix -e secrets/xmrig-always-api-token.age
   agenix -e secrets/xmrig-flexible-api-token.age
   ```

2. **Deploy to zephyr** (local):
   ```bash
   just switch
   # Or: sudo nixos-rebuild switch --flake .#zephyr
   ```

3. **Deploy to nexus** (remote):
   ```bash
   just deploy
   # Or: nix run .#apps.x86_64-linux.colmena -- apply --on nexus
   ```

4. **Verify services are running**:
   ```bash
   systemctl status xmrig-always
   systemctl status xmrig-flexible
   xmrig-api-control status always
   xmrig-api-control status flexible
   ```

## Verification

```bash
# Check both instances are mining
curl -s -H "Authorization: Bearer $(sudo cat /run/agenix/xmrig-always-api-token)" \
  http://127.0.0.1:8081/1/summary | jq '.hashrate.total[0]'

curl -s -H "Authorization: Bearer $(sudo cat /run/agenix/xmrig-flexible-api-token)" \
  http://127.0.0.1:8082/1/summary | jq '.hashrate.total[0]'

# Test GameMode integration (start a game and watch):
tail -f /var/log/gamemode-mining.log
```

## Migration Notes

- **Single XMRig → Dual XMRig**: The old `services.mining.xmrig` is replaced by `services.mining.xmrigDual`
- **Backward compatibility**: Old `xmrig-api-token` still exists but unused
- **Rollback**: If needed, revert to single xmrig by disabling `xmrigDual` and re-enabling `xmrig`

## Troubleshooting

**Services not starting:**
- Check token files exist: `ls -la /run/agenix/xmrig-*`
- Check logs: `journalctl -u xmrig-always -u xmrig-flexible`

**GameMode not pausing:**
- Check GameMode status: `gamemoded -status`
- Check hook logs: `cat /var/log/gamemode-mining.log`
- Test manually: `systemctl stop xmrig-flexible`

**Thread count wrong:**
- Check configured threads: `systemctl show xmrig-always -p ExecStart`
- Set via API: `xmrig-api-control threads 8 flexible`
