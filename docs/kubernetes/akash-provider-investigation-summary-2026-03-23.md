# Akash Provider Investigation Summary

**Date:** 2026-03-23
**Investigation Duration:** ~3 hours
**Status:** ⚠️ **ONGOING** - Partial progress made, root cause still being determined

---

## Executive Summary

Investigated persistent "client is not running. Use .Start() method to start" error affecting Akash provider deployment. Made significant progress identifying multiple contributing factors and implemented partial fixes, but provider stability issue remains unresolved.

---

## Issues Resolved

### 1. ✅ Network Policy Blocking Operator → Kubernetes API
**Problem:** Hostname operator couldn't connect to Kubernetes API server
**Root Cause:** `default-deny-all` network policy blocked egress
**Solution:** Created `allow-operator-egress` network policy
**File:** `kubernetes-manifests/akash-provider/operator-network-policy.yaml`
**Status:** ✅ **FIXED**

### 2. ✅ Flannel Subnet Exhaustion on Sentry
**Problem:** Hostname operator pod stuck in `ContainerCreating`
**Root Cause:** Sentry's Flannel subnet `10.244.0.0/24` exhausted (254 IPs)
**Solution:** Patched hostname operator deployment with `nodeSelector: {"kubernetes.io/hostname": "zephyr"}`
**Status:** ✅ **WORKAROUND APPLIED**

### 3. ✅ Network Policy Blocking Provider → Operator Communication
**Problem:** Provider health checks to hostname operator failing
**Root Cause:** `allow-ingress-from-ingress` policy only allowed traffic from `ingress-system` namespace
**Solution:** Created `allow-provider-to-operator-ingress` network policy
**File:** `kubernetes-manifests/akash-provider/provider-to-operator-network-policy.yaml`
**Status:** ✅ **FIXED**

### 4. ✅ Hardware Discovery Timing Issue
**Problem:** Provider started before inventory operator completed hardware discovery
**Symptoms:** Provider detected 0 nodes on startup
**Solution:** Added 30-second startup delay to provider init script
**Files:**
- `kubernetes-manifests/akash-provider-init-configmap.yaml` (created)
- `kubernetes-manifests/akash-provider-values.yaml` (updated)
**Status:** ✅ **FIXED** - Provider now detects 3 nodes with 5 GPUs

### 5. ✅ Kubernetes API Server Failure
**Problem:** kube-apiserver was stopped/deactivating
**Symptoms:** Provider couldn't connect to Kubernetes API (10.1.1.110:6443)
**Solution:** Restarted kube-apiserver service
**Command:** `ssh zephyr "sudo systemctl restart kube-apiserver"`
**Status:** ✅ **FIXED** - API server back to running

---

## Ongoing Issues

### ⚠️ Provider Stability - ROOT CAUSE IDENTIFIED (2026-03-23 18:15 UTC)

**ROOT CAUSE: Gateway REST Server Missing TLS Certificates**

**Symptoms:**
- Provider starts successfully
- All operators healthy
- Hardware discovery complete (3 nodes, 5 GPUs detected)
- RPC server listening on port 8444 ✓
- **Gateway REST server fails to start** (port 8443)
- Provider shuts down immediately after RPC server starts
- Error: "client is not running. Use .Start() method to start"

**Evidence:**
```
[5:55PM] INF all waitables ready
[5:55PM] INF rpc listening on "0.0.0.0:8444"  ← gRPC server: SUCCESS
[5:55PM] INF received shutdown request err="context canceled"  ← REST gateway: FAILED
```

**Root Cause Analysis:**

The provider's Gateway REST server (`gwrest`) requires TLS certificates to start:
1. `gwrest.NewServer()` called at line 682 of `run.go`
2. `NewServerTLSConfig()` called at line 47 of `gateway/rest/server.go`
3. `GetMTLS()` called to obtain mTLS certificates from account querier
4. **FAILS** because:
   - CertIssuer is not configured (`letsEncrypt.enabled: false`)
   - No TLS cert/key files provided
   - Account querier cannot provide certificates
5. Error returned → Provider setup fails → Context canceled
6. Actual error masked by `context.Canceled` filter (line 747 of run.go)

**Error Flow:**
```
gwrest.ListenAndServeTLS()
  └─> NewServerTLSConfig()
      └─> GetMTLS()
          └─> FAILS (no CertIssuer)
              └─> NewServer() returns error
                  └─> Provider setup fails
                      └─> Context canceled
                          └─> All services shut down
```

**Solution Required:**

Configure TLS certificates for Gateway REST server via one of these options:

**Option 1: Enable Let's Encrypt with Cloudflare DNS-01** (RECOMMENDED)
- Create Kubernetes secret from `secrets/cloudflare-api-token.age`
- Enable `letsEncrypt.enabled: true` in Helm values
- Configure Cloudflare DNS provider for DNS-01 challenge
- Provider will automatically obtain certificates from Let's Encrypt

**Option 2: Provide self-signed certificates**
- Generate self-signed TLS certificates
- Create Kubernetes secret with cert/key
- Mount secret to provider pod
- Configure provider to use certificates

**Option 3: Disable REST gateway** (NOT RECOMMENDED)
- Requires code modification
- Would break provider features that depend on REST API
- Only gRPC server would remain (port 8444)

**Files to Modify:**
1. `kubernetes-manifests/akash-provider-values.yaml` - Enable letsEncrypt
2. Create Kubernetes secret from agenix `cloudflare-api-token.age`
3. Update documentation with certificate setup procedure

**Status:** ⏳ **AWAITING CERTIFICATE CONFIGURATION**

Provider cannot start until Gateway REST server TLS certificates are configured.

---

## Files Modified

### Created
1. `kubernetes-manifests/akash-provider/operator-network-policy.yaml`
2. `kubernetes-manifests/akash-provider/provider-to-operator-network-policy.yaml`
3. `kubernetes-manifests/akash-provider-init-configmap.yaml`

### Modified
1. `kubernetes-manifests/akash-provider-values.yaml` - Added startup delay to init.sh
2. `docs/kubernetes/akash-provider-debug-report-2026-03-23.md` - Comprehensive investigation log

### System Changes
1. Restarted kube-apiserver on zephyr
2. Patched hostname operator deployment with nodeSelector

---

## Current Cluster Status

### Working Components ✅
- Kubernetes control plane (API server, etcd, scheduler, controller-manager)
- All 4 nodes Ready (zephyr, nexus, forge, sentry)
- Hostname operator (running on zephyr)
- Inventory operator (3/4 hardware discovery pods running)
- Network policies configured correctly
- DNS resolution functional
- RPC connectivity verified (akash-rpc.polkachu.com:443)

### Failing Components ❌
- **Akash provider** - CrashLoopBackOff (starts successfully, then crashes after 30-60s)
- Sentry hardware discovery pod - ContainerCreating (Flannel subnet exhaustion, low priority)

---

## Key Learnings

1. **Network Policies are Critical**: Zero-trust network policies require explicit allow rules for all service-to-service communication
2. **Timing Issues Matter**: Kubernetes operators have initialization sequences that must complete before dependent services start
3. **Control Plane Health**: Provider requires healthy API server connection to function
4. **Debugging Strategy**: Systematic elimination of factors (network → timing → control plane) is effective
5. **Log Analysis**: Reading between the lines of error messages is crucial - "context canceled" and "client is not running" are symptoms, not root causes

---

## Recommended Next Steps

1. **Enable Debug Logging**:
   ```bash
   helm upgrade akash-provider akash/provider -n akash-services \
     --set debug="true" -f kubernetes-manifests/akash-provider-values.yaml
   ```

2. **Review Provider Attributes**: Currently empty `attributes: []` on-chain - may need to populate with capabilities

3. **Check Resource Limits**: Current limits are 2 CPU / 2Gi memory - may need to increase to match Helm chart defaults (2 CPU / 4Gi)

4. **Monitor Manifest Service**: Add additional logging to track manifest service lifecycle

5. **Investigate Provider Attributes**: Current on-chain config shows `attributes: []` - may need to populate with cluster capabilities

---

**Document Version:** 1.0
**Created:** 2026-03-23
**Last Updated:** 2026-03-23 17:12 UTC
