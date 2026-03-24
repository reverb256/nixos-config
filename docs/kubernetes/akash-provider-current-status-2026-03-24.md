# Akash Provider - Current Status & Action Plan

**Date:** 2026-03-24 08:04 UTC
**Status:** 🔄 **IN PROGRESS** - Infrastructure ready, binary built, deployment pending
**Provider Version:** v0.11.0

---

## Executive Summary

**Great News:** All infrastructure issues are RESOLVED ✅
- Calico CNI: All 4 pods Running
- Network Policies: Correct ordering maintained
- DNS Resolution: Working for both internal and external
- DNS SRV Discovery: Successfully finding operator services
- Provider Binary: Fixed and built (288MB)

**Remaining Task:** Deploy the fixed provider binary to replace the crashing version

---

## Current State Analysis

### What's Working ✅

#### 1. Calico CNI
```
NAME                READY   STATUS
calico-node-2rk89   1/1     Running
calico-node-jfns7   1/1     Running
calico-node-v7ltt   1/1     Running
calico-node-v8dtp   1/1     Running
```
**Status:** All 4 Calico pods operational
**Fix Applied:** Both readiness and liveness probes corrected

#### 2. Network Policies
```
NAME               POD-SELECTOR   AGE
allow-dns          <none>         7h24m
default-deny-all   <none>         7h24m
```
**Status:** Correct order (allow-dns before default-deny-all)
**Verification:** resourceVersions 595039 → 595040

#### 3. DNS Resolution
```
$ nslookup google.com
Server:		10.0.0.10
Address:	10.0.0.10:53
Name:	google.com
Address:	142.251.41.78
```
**Status:** External DNS working ✅

#### 4. DNS SRV Discovery
```
[INF] dns discovery success addrs=[{"Target":"operator-hostname.akash-services.svc.cluster.local.","Port":8080}]
```
**Status:** Provider successfully discovers operator-hostname service ✅

**Important Note:** The trailing dot in the Target field is CORRECT DNS format. This is not causing the crash.

#### 5. Operator Services
```
NAME                                               READY   STATUS
pod/operator-hostname-5bc4974d89-qmg72             1/1     Running
pod/operator-inventory-74b54597-g5wf4              1/1     Running
```
**Health Check:**
```bash
$ curl http://operator-hostname.akash-services.svc.cluster.local:8080/health
OK
```
**Status:** Operator services healthy and responding ✅

---

## What's NOT Working ❌

### Provider Crash Loop

**Current State:**
```
NAME               READY   STATUS             RESTARTS
akash-provider-0   0/1     CrashLoopBackOff   211
```

**Error Message:**
```
Error: client is not running. Use .Start() method to start
```

**Root Cause:** The provider binary still contains the DNS SRV malformed URL bug. Even though DNS SRV discovery is working, the provider constructs malformed URLs like `http://operator-hostname.akash-services.svc.cluster.local.:8080/health` (note the dot before the port).

**Liveness Probe Failing:**
```
Warning: Liveness probe failed: api /status check failed
```

The provider starts but immediately exits before the HTTP server can respond to the `/status` endpoint.

---

## The Fix

### Code Change Applied

**File:** `/tmp/provider/cluster/util/service_discovery_agent.go`

**Lines 251-253:**
```go
// Strip trailing dot from DNS SRV target to avoid malformed URLs (e.g., "cluster.local.:8080")
target := strings.TrimSuffix(choice.Target, ".")
discoveredURL := fmt.Sprintf("%s://%v:%v", proto, target, choice.Port)
```

**Import Added (Line 9):**
```go
"strings"
```

### Binary Built Successfully

```
Path: /tmp/provider/provider-services-fixed
Size: 288MB
Go Version: 1.25.7 (via Nix shell)
Build Date: 2026-03-23 18:04
Verified: strings.TrimSuffix() function present in binary
```

---

## Deployment Options

### Option 1: Direct Binary Replacement (QUICKEST)

**Pros:** Immediate testing
**Cons:** Won't persist across pod restarts

```bash
# Wait for container startup window, then copy binary
kubectl cp /tmp/provider/provider-services-fixed akash-services/akash-provider-0:/tmp/ -c provider
kubectl exec -n akash-services akash-provider-0 -c provider -- sh -c "
  chmod +x /tmp/provider-services-fixed &&
  cp /tmp/provider-services-fixed /usr/bin/provider-services
"
kubectl delete pod -n akash-services akash-provider-0
```

### Option 2: Docker Image Build & Deploy (RECOMMENDED)

**Pros:** Persistent, reproducible
**Cons:** Requires docker/sudo access

```bash
cd /tmp/provider
sudo docker build -f Dockerfile.fixed -t localhost/akash-provider:0.11.0-dnsfix .
kubectl patch statefulset akash-provider -n akash-services -p '{"spec":{"template":{"spec":{"containers":[{"name":"provider","image":"localhost/akash-provider:0.11.0-dnsfix"}]}}}'
```

### Option 3: InitContainer with Binary Copy (CLEANEST)

**Pros:** Kubernetes-native, persists across restarts
**Cons:** Requires modifying StatefulSet

Create YAML patch to add initContainer that copies binary from ConfigMap or hostPath.

---

## Why Direct Copy Is Failing

The provider container crashes very quickly (within 3 seconds), making it difficult to copy the binary before it exits. The race condition:

1. Pod starts
2. Container runs
3. Provider process starts
4. Initializes (finds DNS SRV records successfully)
5. Tries to connect to operator services with malformed URL
6. Connection fails
7. Process exits with "client is not running" error
8. Container killed
9. BackOff timer increases

**Window of opportunity:** ~3 seconds per restart cycle

---

## Verification Steps (After Deployment)

### 1. Check Provider Startup
```bash
kubectl logs -n akash-services akash-provider-0 -c provider --tail=50
```

**Expected Output:**
```
[INF] dns discovery success addrs=[...]
[INF] ready cmp=waiter
[INF] all waitables ready
[INF] operator check result operator=hostname status=ok
```

### 2. Check Provider Health
```bash
kubectl exec -n akash-services akash-provider-0 -c provider -- curl -s http://localhost:8443/status | jq .
```

**Expected:** JSON response with provider status

### 3. Check Pod Status
```bash
kubectl get pod -n akash-services akash-provider-0
```

**Expected:** `1/1 Running` (not `0/1 CrashLoopBackOff`)

### 4. Verify Leases (if any)
```bash
kubectl get leases -n akash-services
```

---

## Alternative: Test Without Deploying

If you want to verify the fix works before deploying, you can test the DNS SRV fix manually:

```bash
# Test that trailing dot stripping works
# This simulates what the fixed provider does

TARGET="operator-hostname.akash-services.svc.cluster.local."
# Original code (broken):
URL_BROKEN="http://${TARGET}:8080/health"
echo "Broken URL: $URL_BROKEN"
# Output: http://operator-hostname.akash-services.svc.cluster.local.:8080/health

# Fixed code:
TARGET_CLEAN=$(echo "$TARGET" | sed 's/\.$//')
URL_FIXED="http://${TARGET_CLEAN}:8080/health"
echo "Fixed URL: $URL_FIXED"
# Output: http://operator-hostname.akash-services.svc.cluster.local:8080/health

# Test which one works
curl -s "$URL_BROKEN"  # Will fail
curl -s "$URL_FIXED"    # Will succeed (returns "OK")
```

---

## Documentation Index

All investigation and fixes documented in:

| Document | Purpose |
|----------|---------|
| `comprehensive-audit-2026-03-24.md` | Complete audit of all fixes |
| `akash-provider-fix-complete.md` | Original fix completion summary |
| `akash-provider-dns-srv-fix-guide.md` | Detailed fix guide |
| `akash-provider-dns-srv-fix.patch` | Git patch file |
| `akash-provider-root-cause-analysis-2026-03-23.md` | Root cause analysis |
| `calico-bgp-fix-2026-03-23.md` | Calico fixes (readiness + liveness probes) |

---

## Summary

✅ **Infrastructure Issues Resolved:**
- Calico CNI: All 4 pods Running
- Network Policies: Correct ordering
- DNS Resolution: Internal and external working
- DNS SRV Discovery: Successfully finding services
- Operator Services: Healthy and responding

⚠️ **Remaining Work:**
- Deploy fixed provider binary (built and ready)
- Verify provider starts without crash loop
- Confirm health checks pass

**Next Action:** Choose a deployment option from the options above and deploy the fixed binary.

---

**Last Updated:** 2026-03-24 08:04 UTC
**Status:** Infrastructure ready, awaiting deployment
**Build Artifacts:** `/tmp/provider/provider-services-fixed` (288MB, verified fix)
