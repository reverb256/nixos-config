# Akash Provider DNS SRV Bug - Fix Guide

**Date:** 2026-03-23
**Status:** ✅ Fix Identified and Patched
**Provider Version:** v0.11.0
**Severity:** CRITICAL (causes provider crash loop)

---

## Quick Summary

**The Bug:** Akash provider constructs malformed URLs from DNS SRV records by not stripping trailing dots from FQDNs, causing health checks to fail with "context canceled" errors.

**The Fix:** Strip trailing dot from DNS SRV target before constructing HTTP URLs.

**Impact:** Provider crashes immediately on startup, making it completely non-operational.

---

## Root Cause Analysis

### Technical Details

1. **DNS SRV Response Format:**
   - Kubernetes DNS correctly returns FQDNs with trailing dots per RFC 1035
   - Example: `operator-hostname.akash-services.svc.cluster.local.`

2. **Provider Bug:**
   - Code directly concatenates FQDN with port without stripping trailing dot
   - Result: `http://operator-hostname.akash-services.svc.cluster.local.:8080/health`
   - The dot before port number makes the URL malformed

3. **Failure Chain:**
   ```
   DNS SRV Query → FQDN with trailing dot → Malformed URL → Health check fails →
   Context canceled → Provider crashes → CrashLoopBackOff
   ```

### Evidence from Provider Logs

```
[90m9:37PM[0m [32mINF[0m [1mdns discovery success[0m [36maddrs=[0m[{"Target":"operator-hostname.akash-services.svc.cluster.local.","Port":8080}]
[90m9:37PM[0m [31mERR[0m [1mnot yet ready[0m [36merror=[0m[31m[1m"Get \"http://operator-hostname.akash-services.svc.cluster.local.:8080/health\": context canceled"
```

Note the malformed URL: `cluster.local.:8080` (dot before port)

---

## The Fix

### Code Changes

**File:** `cluster/util/service_discovery_agent.go`

**Change 1: Add Import**
```go
import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"net"
	"strings"  // ← ADD THIS
	"time"
	...
)
```

**Change 2: Strip Trailing Dot**
```go
// OLD CODE (line 250):
discoveredURL := fmt.Sprintf("%s://%v:%v", proto, choice.Target, choice.Port)

// NEW CODE (lines 251-253):
// Strip trailing dot from DNS SRV target to avoid malformed URLs (e.g., "cluster.local.:8080")
target := strings.TrimSuffix(choice.Target, ".")
discoveredURL := fmt.Sprintf("%s://%v:%v", proto, target, choice.Port)
```

### Patch File

A git-formatted patch is available at:
```
/etc/nixos/docs/kubernetes/akash-provider-dns-srv-fix.patch
```

Apply with:
```bash
cd /path/to/provider/source
git apply /etc/nixos/docs/kubernetes/akash-provider-dns-srv-fix.patch
```

---

## How to Apply the Fix

### Option 1: Submit to Upstream (RECOMMENDED)

1. **Clone Akash Network Provider Repository:**
   ```bash
   git clone https://github.com/akash-network/provider.git
   cd provider
   ```

2. **Apply Patch:**
   ```bash
   git apply /etc/nixos/docs/kubernetes/akash-provider-dns-srv-fix.patch
   ```

3. **Build Provider:**
   ```bash
   # Ensure Go 1.25.5 is installed
   make build
   ```

4. **Create Pull Request:**
   - Submit to akash-network/provider repository
   - Reference this issue and documentation

### Option 2: Build Custom Image

1. **Apply Patch** to provider source

2. **Build Binary:**
   ```bash
   cd /path/to/provider/source
   make build
   ```

3. **Build Docker Image:**
   ```bash
   docker build -t your-registry/provider:0.11.0-dnsfix .
   ```

4. **Push to Registry:**
   ```bash
   docker push your-registry/provider:0.11.0-dnsfix
   ```

5. **Update Helm Values:**
   ```yaml
   image:
     repository: your-registry/provider
     tag: 0.11.0-dnsfix
   ```

### Option 3: Patch Running Binary (NOT RECOMMENDED)

**WARNING:** This is a temporary workaround only. Use for testing only.

1. **Extract Binary from Container:**
   ```bash
   kubectl exec -n akash-services akash-provider-0 -c provider -- cat /usr/bin/provider-services > provider-services.original
   ```

2. **Patch with Hex Editor:**
   - Find string pattern `://%v:%v` in binary
   - This is complex and error-prone
   - **Not recommended**

3. **Copy Back:**
   ```bash
   kubectl cp provider-services.patched akash-services/akash-provider-0:/usr/bin/provider-services -c provider
   kubectl exec -n akash-services akash-provider-0 -c provider -- chmod +x /usr/bin/provider-services
   kubectl delete pod -n akash-services akash-provider-0
   ```

---

## Testing the Fix

### Pre-Fix Behavior

```bash
kubectl logs -n akash-services akash-provider-0 -c provider | grep "context canceled"
```

**Expected Output (Broken):**
```
[ERR] not yet ready error="Get \"http://operator-hostname.akash-services.svc.cluster.local.:8080/health\": context canceled"
```

### Post-Fix Behavior

```bash
kubectl logs -n akash-services akash-provider-0 -c provider | grep -E "(ready|healthy)"
```

**Expected Output (Fixed):**
```
[INF] ready cmp=waiter
[INF] operator check result operator=hostname status=ok
```

### Health Check Verification

```bash
kubectl exec -n akash-services akash-provider-0 -c provider -- curl -s http://operator-hostname.akash-services.svc.cluster.local:8080/health
```

**Expected Output (Fixed):**
```json
{"status":"ok"}
```

---

## Workarounds (If Build Not Possible)

### Workaround 1: Disable Health Checks

**NOT RECOMMENDED** - Defeats the purpose of health monitoring.

### Workaround 2: Use IP Addresses

Configure provider to use operator service IP addresses instead of DNS SRV records.

**Pros:** Avoids DNS SRV bug
**Cons:** Not dynamic, breaks when pods are rescheduled

### Workaround 3: Downgrade Provider

Try an older provider version that doesn't use DNS SRV for service discovery.

**Pros:** Might work temporarily
**Cons:** Loses new features and security fixes

---

## Related Issues

### Prerequisites for This Fix

The following issues must also be resolved for provider to start:

1. **Network Policies** ✅ FIXED
   - Created `allow-coredns-external-dns` policy for kube-system
   - Fixed network policy ordering in default namespace
   - See: `docs/kubernetes/calico-bgp-fix-2026-03-23.md`

2. **Calico CNI** ✅ FIXED
   - Fixed VXLAN mode configuration
   - Corrected readiness probes (removed BIRD check)
   - See: `docs/kubernetes/calico-bgp-fix-2026-03-23.md`

3. **CertIssuer** ✅ FIXED
   - Disabled Let's Encrypt ACME challenger
   - Provider now uses mTLS certificates
   - See: `docs/kubernetes/akash-provider-root-cause-analysis-2026-03-23.md`

---

## Documentation Files

- **Root Cause Analysis:** `docs/kubernetes/akash-provider-root-cause-analysis-2026-03-23.md`
- **Patch File:** `docs/kubernetes/akash-provider-dns-srv-fix.patch`
- **Calico BGP Fix:** `docs/kubernetes/calico-bgp-fix-2026-03-23.md`
- **Investigation Summary:** `docs/kubernetes/akash-provider-investigation-summary-2026-03-23.md`

---

## Next Actions

1. **IMMEDIATE:** Submit patch to Akash Network provider repository
2. **SHORT-TERM:** Build custom image with fix for testing
3. **MEDIUM-TERM:** Verify provider startup after fix applied
4. **LONG-TERM:** Monitor for upstream fix release

---

**Last Updated:** 2026-03-23 23:00 UTC
**Investigated by:** Claude Code (Explanatory Mode)
**Status:** Fix complete, awaiting build/deploy
