# Loki Verification Issues - 2026-03-12

## Task: Task 1 - Verify Loki Configuration on Sentry

## Summary
Loki is **NOT DEPLOYED** on sentry. The configuration exists but the system has not been rebuilt/redeployed.

## Issues Found

### 1. Loki Service Not Installed
- **Expected**: `systemctl status loki.service` shows "active (running)"
- **Actual**: Unit `loki.service` could not be found
- **Impact**: Loki log aggregation is not functional
- **Root Cause**: Configuration exists in `/etc/nixos/modules/services/monitoring/loki.nix` and is enabled in `/etc/nixos/hosts/sentry/monitoring.nix`, but sentry has not been rebuilt with this configuration

### 2. Configuration Mismatches with Requirements

The current Loki module (`/etc/nixos/modules/services/monitoring/loki.nix`) uses defaults that don't match storage architecture requirements:

| Requirement | Current Default | Required Value | Status |
|-------------|-----------------|----------------|--------|
| Listen Address | `127.0.0.1` | `0.0.0.0` (or `10.1.1.140`) | **MISMATCH** |
| Storage Path | `/var/lib/loki` | `/storage/loki` | **MISMATCH** |
| Retention Period | `30d` | `30d` | OK |
| Port | `3100` | `3100` | OK |

### 3. IP Address Discrepancy
- **Task specified**: `10.1.1.40`
- **Actual sentry IP**: `10.1.1.140`
- **Impact**: Documentation/plan references incorrect IP

### 4. Storage Not Provisioned
- **Expected**: `/storage/loki` directory exists
- **Actual**: `/storage` directory exists but is empty
- **Impact**: Even if Loki is started, it will use `/var/lib/loki` (default) instead of the centralized `/storage/loki`

## Required Actions Before Promtail Deployment

1. **Fix sentry monitoring configuration** to override Loki defaults:
   ```nix
   # In /etc/nixos/hosts/sentry/monitoring.nix
   services.monitoring.loki = {
     enable = true;
     listenAddress = "0.0.0.0";  # Listen on all interfaces for cluster access
     dataDir = "/storage/loki";   # Use centralized storage
     retentionPeriod = "30d";     # Already the default
   };
   ```

2. **Ensure `/storage` filesystem is mounted** on sentry
   - Currently `/storage` exists but appears empty
   - Verify storage mount configuration in sentry's `hardware-configuration.nix`

3. **Rebuild sentry** with corrected configuration:
   ```bash
   just switch sentry
   ```

4. **Verify Loki is running** after rebuild:
   ```bash
   ssh sentry "systemctl status loki.service"
   curl -s http://10.1.1.140:3100/ready
   ```

## Module Review

The Loki module at `/etc/nixos/modules/services/monitoring/loki.nix` is well-structured with:
- Proper option definitions with defaults
- Firewall rule for tailscale0 interface
- All required Loki configuration sections
- Retention policy configurable

However, it listens on `127.0.0.1` by default, which means only local Promtail can send logs. For cluster-wide log aggregation, it needs to listen on the node IP (`10.1.1.140`) or `0.0.0.0`.

## Testing Status

| Check | Status |
|-------|--------|
| Config file exists | PASS |
| Module imported | PASS |
| `loki.enable = true` | PASS |
| Listen address: 10.1.1.40:3100 | FAIL - Not configured, wrong IP |
| Storage path: /storage/loki | FAIL - Default is /var/lib/loki |
| Retention: 30 days | PASS - Default matches |
| Service running | FAIL - Service not installed |
| HTTP endpoint responds | FAIL - Service not running |

## Recommendation

**DO NOT deploy Promtail until Loki is properly configured and running.** The storage architecture plan assumes Loki is the central log aggregation point. Without it, Promtail will have nowhere to send logs.

Next steps:
1. Update sentry monitoring configuration with correct overrides
2. Verify `/storage` mount is working
3. Rebuild sentry
4. Re-run this verification task
5. Only then proceed to Task 2 (Promtail deployment)
