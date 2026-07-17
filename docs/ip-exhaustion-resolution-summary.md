# Sentry "IP Exhaustion" Resolution Summary

## ✅ Issues Resolved

### 1. Pod Deployment Failures on Sentry
- **Symptom**: New pods stuck in `ContainerCreating` with "failed to load flannel 'subnet.env'" error
- **Root Cause**: Flannel daemonset pod restarted, CNI plugin couldn't find subnet configuration file
- **Fix Applied**: Deleted and recreated Flannel pod on Sentry
- **Result**: All affected pods (cloudflared, operator-inventory, test-ip) started successfully
- **Impact**: 5-10 minutes of deployment failures, no data loss

### 2. Documentation Created
- ✅ **Debug Report**: `docs/sentry-instability-debug-2026-03-21.md`
  - Complete timeline and root cause analysis
  - Technical details of Flannel subnet allocation
  - Prevention measures for future incidents

- ✅ **STATUS.md Updated**: Added resolved issue to Known Issues table

### 3. kube-apiserver-logger Module
- ✅ **Module Created**: `modules/system/kube-apiserver-logger.nix`
- ✅ **Imported**: Added to `modules/default.nix` (line 48)
- ⚠️ **Not Deployed**: Needs to be enabled in `hosts/zephyr/configuration.nix`

## ⚠️ Outstanding Issues

### 1. Orphaned kube-apiserver Service on Sentry
**Finding**: Broken systemd service trying to connect to non-existent local etcd
- Service is inactive (not causing current problems)
- Represents cleanup debt from previous architecture
- Cannot disable via systemctl (NixOS read-only filesystem)

**Resolution Required**: Add to Sentry's NixOS configuration:
```nix
# hosts/sentry/configuration.nix
systemd.services.kube-apiserver.enable = lib.mkForce false;
```

**Priority**: 🟢 LOW (service is already inactive, cleanup only)

### 2. Deploy kube-apiserver-logger
**Module Status**: Created and imported, but not enabled

**Action Required**: Enable on Zephyr (control plane node):
```nix
# hosts/zephyr/configuration.nix
services.kube-apiserver-logger = {
  enable = true;
  logFile = "/var/log/kube-apiserver-restarts.log";
};
```

**Priority**: 🟡 MEDIUM (monitoring for future incidents)

## Cluster Health Status

**All Systems Operational:**
- ✅ 4/4 nodes Ready
- ✅ 0 failing pods
- ✅ Flannel CNI operational on all nodes
- ✅ Control plane stable on Zephyr
- ✅ No IP exhaustion (198/254 IPs used on Sentry)

## Flannel Subnet Status

| Node | Subnet | Usage | Status |
|------|--------|-------|--------|
| Zephyr | 10.244.1.0/24 | ~150/254 | 🟢 Normal |
| Nexus | 10.244.3.0/24 | ~120/254 | 🟢 Normal |
| Sentry | 10.244.2.0/24 | 198/254 | 🟢 Normal |
| Forge | 10.244.0.0/24 | ~180/254 | 🟢 Normal |

**Conclusion**: No actual IP exhaustion exists. The error was a transient CNI initialization issue.

## Recommendations

### Immediate (Next Session)
1. Enable kube-apiserver-logger on Zephyr
2. Disable orphaned kube-apiserver service on Sentry via NixOS config
3. Deploy changes with `just deploy`

### Future Improvements
1. Add Flannel health checks to monitoring stack
2. Consider CNI plugin readiness gates for critical pods
3. Regular audit of systemd services for orphaned units
4. Document centralized control plane architecture (Zephyr-only)

## Technical Insights

`★ Insight ─────────────────────────────────────`
- **CNI Dependency**: All pod networking depends on single file (`/run/flannel/subnet.env`)
- **Flannel Self-Healing**: Automatic restart works, but manual intervention faster
- **NixOS Immutable**: Systemd changes must go through config, not direct commands
- **Centralized Control Plane**: Only Zephyr runs API server/etcd, Sentry was misconfigured
`─────────────────────────────────────────────────`

## Files Modified

- ✅ `docs/sentry-instability-debug-2026-03-21.md` (created)
- ✅ `docs/ip-exhaustion-resolution-summary.md` (created)
- ✅ `STATUS.md` (updated with resolved issue)
- ✅ `modules/system/kube-apiserver-logger.nix` (created)
- ✅ `modules/default.nix` (imported kube-apiserver-logger)

## Next Actions

```bash
# 1. Enable API server logger on Zephyr
# Edit hosts/zephyr/configuration.nix, add:
# services.kube-apiserver-logger.enable = true;

# 2. Disable orphaned API server on Sentry
# Edit hosts/sentry/configuration.nix, add:
# systemd.services.kube-apiserver.enable = lib.mkForce false;

# 3. Deploy changes
just deploy

# 4. Verify API server logger
journalctl -u kube-apiserver-logger -f
```

---

**Incident Duration**: 15 minutes
**Resolution Time**: 5 minutes
**Severity**: Medium (pods failing) / Low (quick fix, no data loss)
**User Impact**: Temporary deployment failures only
**Data Loss**: None
**SLA Impact**: None (resolved before affecting production workloads)
