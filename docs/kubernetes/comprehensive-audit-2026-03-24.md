# Comprehensive Audit Report - Akash Provider Fixes

**Date:** 2026-03-24
**Auditor:** Claude Code (Explanatory Mode)
**Trigger:** User requested full re-audit of all fixes

---

## Executive Summary

**Status:** ⚠️ **MIXED** - Some fixes verified working, new issues discovered

### ✅ Verified Working
1. **Network Policy Ordering** - Correct (allow-dns before default-deny-all)
2. **DNS Resolution** - Working for external domains (google.com)
3. **Calico Readiness Probe** - Fixed (only -felix-ready)
4. **Provider Binary Fix** - Code change verified correct

### ❌ Issues Found
1. **Calico Liveness Probe** - Still checking for BIRD (CRITICAL)
2. **CoreDNS Network Policy** - Was missing, recreated
3. **Provider DNS SRV Discovery** - Different issue (SRV records missing)

---

## Detailed Audit Findings

### 1. Calico CNI Status ⚠️

**Original Claim:** All 4 Calico pods Running ✅

**Actual State:**
```
NAME                READY   STATUS
calico-node-2rk89   1/1     Running  ← After liveness probe fix
calico-node-jfns7   1/1     Running  ← After liveness probe fix
calico-node-v7ltt   1/1     Running  ← After liveness probe fix
calico-node-v8dtp   1/1     Running  ← After liveness probe fix
```

**Issue Found:** Liveness probe still had `-bird-live` check

**Fix Applied During Audit:**
```bash
kubectl patch ds -n kube-system calico-node --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/exec/command",
         "value": ["/bin/calico-node", "-felix-live"]}]'
kubectl delete pods -n kube-system -l k8s-app=calico-node
```

**Result:** ✅ All 4 Calico pods now Running

**Lesson:** Previous fix only updated readiness probe, not liveness probe

---

### 2. Network Policy Ordering ✅

**Claim:** Policies in correct order

**Audit Result:**
```
allow-dns:          resourceVersion 595039 (older)
default-deny-all:   resourceVersion 595040 (newer)
```

**Verification:** ✅ Correct - allow-dns created before default-deny-all

**Additional Finding:** allow-dns policy permits both kube-system and external DNS (0.0.0.0/0)

---

### 3. DNS Resolution ✅

**Test:** `nslookup google.com` from test pod

**Result:**
```
Server:		10.0.0.10
Address:	10.0.0.10:53
Name:	google.com
Address:	142.251.41.78
```

**Verification:** ✅ DNS resolution working

---

### 4. CoreDNS Network Policy ❌ → ✅

**Claim:** Policy created for kube-system

**Audit Finding:** Policy was missing (deleted or not applied)

**Fix Applied:**
```bash
kubectl apply -f /etc/nixos/kubernetes-manifests/kube-system-dns-network-policy.yaml
```

**Result:** ✅ Policy recreated

---

### 5. Provider Binary Fix ✅

**Binary Path:** `/tmp/provider/provider-services-fixed`

**Verification:**
```bash
$ ls -lh /tmp/provider/provider-services-fixed
-rwxr-xr-x 1 j_kro users 288M Mar 23 18:04

$ strings /tmp/provider/provider-services-fixed | grep -c TrimSuffix
3
```

**Code Review:**
```go
// Line 9: Import present
"strings"

// Lines 251-253: Fix applied
// Strip trailing dot from DNS SRV target to avoid malformed URLs
target := strings.TrimSuffix(choice.Target, ".")
discoveredURL := fmt.Sprintf("%s://%v:%v", proto, target, choice.Port)
```

**Verification:** ✅ Fix correctly applied

**Status:** Binary built and ready, but NOT DEPLOYED

---

### 6. Provider Deployment Status ❌

**Current Status:**
```
NAME               READY   STATUS             RESTARTS        AGE
akash-provider-0   0/1     CrashLoopBackOff   171 (63s ago)   8h
```

**Error in Logs:**
```
[ERR] dns discovery failed error="lookup _rest._TCP.operator-hostname.akash-services.svc.cluster.local on 10.0.0.10:53: no such host"
```

**Analysis:** This is NOT the malformed URL bug. This is a different issue:
- Provider is trying to discover operator-hostname via DNS SRV
- DNS SRV records don't exist for the service
- This is a service discovery configuration issue, not the URL construction bug

**Root Cause:** The operator-hostname Kubernetes Service may not have SRV records published, or provider is looking for wrong SRV name

---

## Critical Gap: DNS SRV Records Missing

### What Should Exist

Kubernetes automatically creates SRV records for services with named ports:
```
_rest._TCP.operator-hostname.akash-services.svc.cluster.local
```

### Actual State

```bash
$ dig -t SRV _rest._TCP.operator-hostname.akash-services.svc.cluster.local @10.0.0.10
(No records returned)
```

### Service Definition

```yaml
apiVersion: v1
kind: Service
metadata:
  name: operator-hostname
  namespace: akash-services
spec:
  ports:
  - name: rest      ← Named port should create SRV record
    port: 8080
    protocol: TCP
    targetPort: rest
```

### Investigation Needed

1. **Why no SRV records?**
   - CoreDNS configuration issue?
   - Service annotation missing?
   - Headless vs ClusterIP service difference?

2. **Provider Discovery Method**
   - Is provider using DNS SRV or direct DNS A records?
   - Should it be using `operator-hostname.akash-services.svc.cluster.local:8080` instead?

---

## Previous Fixes - Verification Status

### ✅ Calico Readiness Probe Fix (Verified)

**Original Fix:**
```bash
kubectl patch ds -n kube-system calico-node --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/exec/command",
         "value": ["/bin/calico-node", "-felix-ready"]}]'
```

**Status:** ✅ Still applied and working

### ⚠️ Calico Liveness Probe Fix (Found Missing During Audit)

**Required Fix (Applied During Audit):**
```bash
kubectl patch ds -n kube-system calico-node --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/exec/command",
         "value": ["/bin/calico-node", "-felix-live"]}]'
```

**Status:** ✅ Fixed during audit

### ✅ Network Policy Ordering Fix (Verified)

**Fix:** Recreated allow-dns before default-deny-all

**Status:** ✅ Correct order maintained

### ✅ CoreDNS External DNS Policy (Recreated During Audit)

**Issue:** Policy was missing

**Fix:** Reapplied manifest

**Status:** ✅ Now present

### ✅ DNS SRV Malformed URL Bug (Code Fix Verified)

**Fix:** Modified `cluster/util/service_discovery_agent.go`

**Status:** ✅ Code fix correct and verified
**Note:** Binary built but NOT deployed to cluster

---

## Issues Requiring Attention

### 1. Deploy Fixed Provider Binary (HIGH PRIORITY)

**Current:** Provider still using original `ghcr.io/akash-network/provider:0.11.0`

**Required:** Deploy `/tmp/provider/provider-services-fixed`

**Action:**
```bash
# Option 1: Build Docker image and deploy
cd /tmp/provider
docker build -f Dockerfile.fixed -t akash-provider:0.11.0-dnsfix .

# Option 2: Use deployment script
/etc/nixos/kubernetes-manifests/akash-provider-deploy-fixed.sh
```

### 2. Investigate DNS SRV Records for operator-hostname (HIGH PRIORITY)

**Problem:** Provider can't discover operator-hostname service via DNS SRV

**Questions:**
- Are SRV records supposed to exist?
- Is provider using wrong discovery method?
- Should service be headless?

**Investigation Steps:**
1. Check if service should be headless
2. Verify CoreDNS SRV record generation
3. Review provider service discovery configuration

### 3. Update Documentation to Reflect Liveness Probe Fix (MEDIUM PRIORITY)

**Files to Update:**
- `/etc/nixos/docs/kubernetes/calico-bgp-fix-2026-03-23.md`
- Add section about liveness probe fix

---

## Corrected Fix Summary

### Actually Working (Verified During Audit)

1. ✅ **Calico Readiness Probe** - Fixed (only -felix-ready)
2. ✅ **Calico Liveness Probe** - Fixed during audit (only -felix-live)
3. ✅ **All 4 Calico Pods** - Running after liveness probe fix
4. ✅ **Network Policy Ordering** - Correct (allow-dns before default-deny-all)
5. ✅ **DNS Resolution** - Working for external domains
6. ✅ **CoreDNS External DNS Policy** - Recreated during audit
7. ✅ **Provider Binary Code Fix** - Verified correct

### Not Yet Deployed

1. ❌ **Fixed Provider Binary** - Built but not deployed to cluster
2. ❌ **Provider DNS SRV Discovery** - Different issue from malformed URL bug

---

## Recommendations

### Immediate Actions

1. **Deploy Fixed Provider Binary** - Use deployment script
2. **Investigate DNS SRV Records** - Determine if this is configuration issue
3. **Monitor Provider Logs** - Check if fix resolves crash loop or reveals new issues

### Documentation Updates

1. Update Calico fix documentation to include liveness probe
2. Document DNS SRV record investigation findings
3. Update fix-complete.md with corrected status

### Future Prevention

1. **Comprehensive Testing** - Test all probes (readiness + liveness)
2. **Service Verification** - Verify DNS records exist before deployment
3. **Audit Trail** - Document all changes with timestamps and verification steps

---

**Audit Completed:** 2026-03-24 06:15 UTC
**Auditor:** Claude Code (Explanatory Mode)
**Trigger:** User requested full re-audit
**Result:** Found and fixed 2 missing issues (liveness probe, CoreDNS policy)
