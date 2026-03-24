# Akash Provider "Client Is Not Running" - Root Cause Analysis

**Date:** 2026-03-23
**Status:** ⚠️ **INVESTIGATION ONGOING** - Startup delay implemented, but "context canceled" persists

---

## Executive Summary

After 36+ hours of debugging, we've identified that the "client is not running" error has **multiple root causes**:

### 1. ✅ **RESOLVED: Network Policy Blocking Provider → Operators** (FIXED)

**Problem:** The hostname operator couldn't connect to Kubernetes API server
**Root Cause:** `default-deny-all` network policy blocked egress to Kubernetes API
**Solution:** Created `allow-operator-egress` network policy
**Status:** ✅ **FIXED** - Hostname operator now running on zephyr

### 2. ✅ **RESOLVED: Flannel Subnet Exhaustion on Sentry** (WORKAROUND)

**Problem:** Hostname operator pod stuck in `ContainerCreating`
**Root Cause:** Sentry's Flannel subnet `10.244.0.0/24` exhausted (254 IPs)
**Solution:** Patched hostname operator deployment with `nodeSelector: {"kubernetes.io/hostname": "zephyr"}`
**Status:** ✅ **WORKAROUND APPLIED** - Operator now runs on zephyr

### 3. ✅ **RESOLVED: Network Policy Blocking Provider → Hostname Operator** (FIXED)

**Problem:** Provider health checks to hostname operator failing
**Root Cause:** `allow-ingress-from-ingress` policy only allowed traffic from `ingress-system` namespace
**Solution:** Created `allow-provider-to-operator-ingress` network policy
**Status:** ✅ **FIXED** - Provider can now reach hostname operator `/health` endpoint

### 4. ⚠️ **PARTIALLY RESOLVED: Provider Shutdown Due to "Context Canceled"**

**Problem:** Provider receives shutdown request immediately after startup
**Symptoms:**
```
[4:56PM] INF all waitables ready
[4:56PM] INF rpc listening on "0.0.0.0:8444"
[4:56PM] INF received shutdown request err="context canceled"
[4:56PM] Error: client is not running. Use .Start() method to start
```

**Root Cause:** **TIMING ISSUE** - Provider starts before inventory operator completes hardware discovery
- Provider queries inventory operator for cluster resources
- Inventory operator returns **0 nodes** (hardware discovery not complete)
- Provider shuts down due to "context canceled"

**Evidence:**
- Provider logs: `cluster resources dump={"nodes":[],"total_allocatable":{...}}`
- Inventory operator logs show discovery in progress but not complete
- Hardware discovery pods still running

---

## Current Status

### Working Components ✅
- Hostname operator: **RUNNING** on zephyr (10.244.1.121:8080)
- Health check: **PASSING** (status=200)
- Network policies: **CONFIGURED** correctly
- DNS resolution: **WORKING**
- RPC connectivity: **VERIFIED** (can reach akash-rpc.polkachu.com:443)

### Failing Components ❌
- Provider pod: **CrashLoopBackOff** (shuts down 30s after startup)
- Cluster resources: **0 nodes detected** (should be 4 nodes)
- Context: **Canceled immediately after startup**

---

## Root Cause: Race Condition

**The provider starts too quickly** - it queries the inventory operator for cluster resources before the inventory operator has finished:

1. **Hardware Discovery** (15-30 seconds per node):
   - Spawns discovery pods on each node
   - Collects GPU/CPU/memory information
   - Reports back to inventory operator

2. **Provider Startup** (starts immediately):
   - Waits for hostname operator (✅ now working)
   - Queries inventory operator for cluster resources
   - Gets **0 nodes** (discovery not complete)
   - Shuts down with "context canceled" error

---

## Solutions

### Option 1: Add Startup Delay to Provider (QUICKEST)

Add a delay in the provider's init script to wait for inventory operator to be ready:

```yaml
scripts:
  init.sh: |
    #!/bin/bash
    set -x

    # ... existing key import code ...

    # Wait for inventory operator to be ready
    echo "Waiting for inventory operator to complete hardware discovery..."
    for i in $(seq 1 30); do
      NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
      if [ "$NODE_COUNT" -ge 3 ]; then
        echo "✓ Inventory operator ready ($NODE_COUNT nodes detected)"
        break
      fi
      echo "Waiting for nodes... ($i/30)"
      sleep 2
    done

    # Continue with rest of init...
```

### Option 2: Configure Provider to Tolerate Empty Cluster

Add provider configuration to allow starting with 0 nodes and wait for nodes to appear:

```yaml
env:
  - name: AKASH_PROVIDER_MIN_NODES
    value: "0"
  - name: AKASH_PROVIDER_STARTUP_TIMEOUT
    value: "120s"  # Wait 2 minutes for nodes
```

### Option 3: Pre-warm Inventory Operator Cache

Configure inventory operator to preload node data before provider starts:

```yaml
inventory:
  cache:
    enabled: true
    ttl: 300s
  prewarm:
    enabled: true
    timeout: 60s
```

---

## Update: 2026-03-23 17:10 UTC

### CRITICAL DISCOVERY: Kubernetes API Server Failure

**Root Cause Identified:** ⚠️ **KUBE-APISERVER WAS STOPPED**

**Timeline of Discovery:**
1. Investigated "manifest service terminated with error" logs
2. Found connection error: `The connection to the server 10.1.1.110:6443 was refused`
3. Checked kube-apiserver status: `deactivating (stop-sigterm)`
4. **ROOT CAUSE:** Control plane failure preventing manifest service from connecting to Kubernetes API

**Evidence:**
```
kube-apiserver.service - Kubernetes APIServer Service
   Active: deactivating (stop-sigterm) since Mon 2026-03-23 17:06:13 UTC
```

**Resolution Attempt:**
- ✅ Restarted kube-apiserver: `systemctl restart kube-apiserver`
- ✅ API server back to `active (running)`
- ✅ Provider pod restarted successfully
- ❌ **Provider STILL crashes** after 30-60 seconds with "client is not running"

**Current Status:**
- Provider starts successfully
- Detects 3 nodes with 5 GPUs (hardware discovery working)
- RPC server listening on port 8444
- Manifest service initializes
- **Then abruptly shuts down** without clear error message

**Revised Analysis:**
The kube-apiserver failure was **A CONTRIBUTING FACTOR**, but not the sole root cause. The provider is still crashing even with:
- ✅ Kubernetes API server running
- ✅ Hardware discovery complete (3 nodes, 5 GPUs)
- ✅ All operators healthy
- ✅ Network policies configured correctly

**ROOT CAUSE IDENTIFIED (2026-03-23 18:00 UTC):**

**Gateway REST Server TLS Configuration Missing**

The provider's Gateway REST server (`gwrest`) requires TLS certificates to start. The error flow:

1. `gwrest.NewServer()` is called at line 682 of `run.go`
2. `NewServerTLSConfig()` is called at line 47 of `gateway/rest/server.go`
3. `GetMTLS()` is called to obtain mTLS certificates
4. **FAILS** because:
   - No CertIssuer configured in context
   - No `--gateway-tls-cert` / `--gateway-tls-key` flags provided
5. Error returned → Provider setup fails → Context canceled
6. Error message is **masked** by "context canceled" filter at line 747

**Evidence:**
- Gateway gRPC server: **successfully** listening on `0.0.0.0:8444`
- Gateway REST server: **failing** on `0.0.0.0:8443` (TLS requirement)
- Zero logs from manifest service (never starts due to setup failure)
- Shutdown happens **immediately** after RPC server starts (no delay)

**Solution Required:**

The Gateway REST server requires TLS certificates from a CertIssuer. Options:

**Option 1: Enable Let's Encrypt with Cloudflare DNS-01** (RECOMMENDED)
1. Create Kubernetes secret from agenix secret `secrets/cloudflare-api-token.age`
2. Configure provider Helm values:
   ```yaml
   letsEncrypt:
     enabled: true
     providers:
       cloudflare:
         enabled: true
         apiToken: <from-secret>
   ```
3. Ensure provider domain (provider.reverb256.ca) has DNS pointing to cluster
4. Cloudflare DNS-01 challenge will create TXT records for validation

**Option 2: Provide self-signed certificates**
1. Generate self-signed TLS certificates
2. Create Kubernetes secret with cert/key
3. Mount secret to provider pod
4. Configure provider to use certificates

**Option 3: Disable REST gateway** (LAST RESORT)
- Requires code modification to skip gwrest initialization
- Provider would use gRPC server only (port 8444)
- May break some provider features that depend on REST API

**Files to Modify:**
- `kubernetes-manifests/akash-provider-values.yaml` - Enable letsEncrypt
- Create Kubernetes secret from agenix secret
- Update documentation with certificate setup

**Cloudflare API Token:**
- Location: `secrets/cloudflare-api-token.age` (agenix encrypted)
- Required permissions: Zone:DNSEdit, Zone:Zone
- Current usage: Cloudflare tunnel (cloudflared)
- Can be reused for Let's Encrypt DNS-01 challenge

---

## Files Modified

1. **`kubernetes-manifests/akash-provider/operator-network-policy.yaml`** (CREATED)
   - Allows operators to access Kubernetes API server

2. **`kubernetes-manifests/akash-provider/provider-to-operator-network-policy.yaml`** (CREATED)
   - Allows provider to connect to hostname/inventory operators

3. **Hostname operator deployment** (PATCHED)
   - Added `nodeSelector: {"kubernetes.io/hostname": "zephyr"}`
   - Avoids sentry's Flannel subnet exhaustion

---

## Next Steps

**RECOMMENDED:** Implement **Option 1** (add startup delay to provider init script)

This is the quickest fix that addresses the root cause without requiring Helm chart modifications or complex configuration changes.

---

## Technical Details

### Network Architecture

```
Provider Pod (zephyr: 10.244.1.115)
    ↓ (network policy: allow-provider-egress)
Hostname Operator (zephyr: 10.244.1.121:8080)
    ↓ (health check: /health)
Provider Service (bidengine.Status())
    ↓ (returns: "not running" if lifecycle.Done())
```

### Error Flow

1. **Provider starts** → Queries inventory operator gRPC (port 8081)
2. **Inventory operator** → Returns 0 nodes (discovery incomplete)
3. **Provider** → Context canceled → Shuts down
4. **Health check** → Calls `bidengine.Status()` → Returns "not running"

### Key Code Locations

- **Bidengine lifecycle:** `/tmp/provider-source/bidengine/service.go` (line 255-259)
- **Waiter implementation:** `/tmp/provider-source/operator/waiter/waiter.go` (line 58-81)
- **Hostname operator check:** `/tmp/provider-source/cluster/kube/operators/clients/hostname/client.go` (line 66-83)
- **Provider run command:** `/tmp/provider-source/cmd/provider-services/cmd/run.go` (line 554, 740)

---

**Document Version:** 1.0
**Created:** 2026-03-23
**Last Updated:** 2026-03-23 16:56 UTC
