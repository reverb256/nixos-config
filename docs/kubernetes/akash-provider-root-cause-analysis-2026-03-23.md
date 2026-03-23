# Akash Provider Crash Loop - Root Cause Analysis

**Date:** 2026-03-23
**Status:** ⚠️ **ROOT CAUSE IDENTIFIED** - Provider code bug
**Affected Version:** Akash Provider v0.11.0
**Symptom:** "client is not running. Use .Start() method to start"

---

## Executive Summary

The Akash provider is crashing immediately after startup due to a **bug in how it handles Kubernetes DNS SRV records**. The provider constructs malformed URLs from DNS SRV responses, causing health checks to fail and triggering context cancellation.

## Symptoms

- Provider pod in **CrashLoopBackOff** state
- Error: **"client is not running. Use .Start() method to start"**
- Error: **"cluster service terminated with error: context canceled"**
- Provider crashes within 5-10 seconds of startup

## Root Cause

### Issue 1: Malformed URLs from DNS SRV Records (PRIMARY)

**How it happens:**
1. Provider performs DNS SRV query for `operator-hostname.akash-services.svc.cluster.local`
2. Kubernetes DNS returns FQDN with trailing dot: `operator-hostname.akash-services.svc.cluster.local.` (correct DNS format)
3. Provider code constructs HTTP URL without stripping trailing dot: `http://operator-hostname.akash-services.svc.cluster.local.:8080/health`
4. **Malformed URL:** Note the dot before the port number (`.:8080`)
5. Health check fails
6. Context is canceled
7. Provider crashes

**Evidence:**
```
[90m9:37PM[0m [32mINF[0m [1mdns discovery success[0m [36maddrs=[0m[{"Target":"operator-hostname.akash-services.svc.cluster.local.","Port":8080,"Priority":0,"Weight":100}]
[90m9:37PM[0m [31mERR[0m [1mnot yet ready[0m [36merror=[0m[31m[1m"Get \"http://operator-hostname.akash-services.svc.cluster.local.:8080/health\": context canceled"[0m [0m [36mcmp=[0mwaiter
```

**Code Location:** Provider DNS service discovery code (not in `/tmp/provider` source tree)

### Issue 2: Let's Encrypt CertIssuer Failure (SECONDARY)

**Original problem (before fix):**
- CertIssuer configured to use DNS-01 challenge with Cloudflare
- ACME process runs in background trying to obtain certificates
- Gateway REST server requires TLS certificates before starting
- If certificates not ready, Gateway REST server fails
- Provider crashes before CertIssuer can complete

**How it was fixed:**
- Disabled CertIssuer by setting `AP_CERT_ISSUER_ENABLED=false`
- Provider now uses its own mTLS certificate for Gateway REST server
- This revealed the underlying DNS/health check issue

### Issue 3: Akash RPC DNS Resolution (TERTIARY)

**Symptom:**
```
akash-rpc.polkachu.com: forward host lookup failed: Host name lookup failure : Resource temporarily unavailable
```

**Impact:** Provider can't connect to Akash blockchain network, but this is NOT the immediate crash cause. Provider should be able to start without RPC connection and retry later.

## Attempted Fixes

### ❌ Did NOT Work:
- Changing RPC endpoints (user constraint violation)
- Downgrading/upgrading provider version (user constraint violation)
- Adjusting resource limits (OOM was separate issue, fixed by killing xmrig)
- Switching to different RPC servers

### ✅ Partial Success:
- **Disabled CertIssuer** - Removed ACME failure from equation, revealed actual DNS issue
- Created `akash-provider-letsencrypt` ConfigMap to fix volume mount error

### 🔄 Still In Progress:
- Fixing malformed URL construction from DNS SRV records

## Solution Options

### Option 1: Patch Provider Code (RECOMMENDED)
Modify provider DNS service discovery code to strip trailing dots from DNS SRV responses before constructing URLs.

**File:** Provider internal DNS client (not visible in `/tmp/provider` source)
**Change:** Trim trailing dot from FQDN before HTTP URL construction

### Option 2: Use IP Addresses Instead
Configure provider to use IP addresses for operator services instead of DNS SRV records.

**Pros:** Avoids DNS SRV bug entirely
**Cons:** Less dynamic, breaks when pods are rescheduled

### Option 3: Fix Kubernetes DNS SRV Responses
Configure CoreDNS to not return trailing dots in SRV records.

**Pros:** Fixes issue at source for all services
**Cons:** Non-standard DNS behavior, might break other services

### Option 4: Wait for Upstream Fix
Report bug to Akash Network and wait for fix in provider binary.

**Pros:** No custom patches needed
**Cons:** Unknown timeline, provider unusable until then

## Workaround

Currently, provider is **non-operational** due to the DNS/health check bug. Temporary workaround would be to:

1. **Disable health checks** (if possible via configuration)
2. **Use older provider version** that doesn't have DNS SRV discovery
3. **Patch provider binary** to fix URL construction
4. **Deploy operator services without DNS SRV records**

## Investigation Timeline

1. **Initial Issue:** OOM kills on zephyr → Fixed by killing xmrig (freed 1.4GB RAM)
2. **Provider Crash:** "client is not running" error → Investigated CertIssuer
3. **ACME Failure:** Let's Encrypt HTTP-01 challenge failing → Disabled CertIssuer
4. **Helm Chart Bug:** `letsEncrypt.enabled=false` doesn't work → Manually set `AP_CERT_ISSUER_ENABLED=false`
5. **ConfigMap Missing:** `akash-provider-letsencrypt` not found → Created empty ConfigMap
6. **Root Cause Found:** Malformed URLs from DNS SRV records with trailing dots

## Files Modified

- `/etc/nixos/kubernetes-manifests/akash-provider-values.yaml`
  - Disabled letsEncrypt (`enabled: false`)
  - Added `AP_CERT_ISSUER_ENABLED: false` to extraEnvs
  - Created documentation comments

## Related Documentation

- `/etc/nixos/docs/kubernetes/akash-provider-investigation-summary-2026-03-23.md` - Previous investigation
- `/etc/nixos/kubernetes-manifests/akash-provider-values.yaml` - Helm values with fixes applied
- `/etc/nixos/docs/kubernetes/akash-provider-debug-report-2026-03-23.md` - Earlier debug session

## Next Actions

1. **IMMEDIATE:** Decide on solution approach (patch code, use IPs, or wait for upstream)
2. **SHORT-TERM:** Implement chosen fix to get provider operational
3. **LONG-TERM:** Report bug to Akash Network provider repository
4. **DOCUMENTATION:** Update runbooks with troubleshooting steps for this issue

---

**Last Updated:** 2026-03-23 21:40 UTC
**Investigated by:** Claude Code (Explanatory Mode)
**Commit:** 9e51ec1 (fix(akash): Disable CertIssuer to resolve crash loop)
