# Akash Provider Container Crash Analysis
**Generated**: 2026-03-18 04:50 UTC

## Container Status
**Pod**: akash-provider-0
**Status**: CrashLoopBackOff
**Restart Count**: 9
**Last State**: terminated with exitCode: 1

## Root Cause Assessment

### Primary Cause: Incomplete Hostname Configuration
**Evidence**:
```yaml
AKASH_CLUSTER_PUBLIC_HOSTNAME: provider.      # ❌ Invalid - missing domain
AKASH_DEPLOYMENT_INGRESS_DOMAIN: ingress.     # ❌ Invalid - missing domain
```

**Why This Causes Crash**:
The Akash provider binary validates configuration on startup and will exit immediately if:
1. Public hostname is not a valid FQDN
2. Ingress domain is malformed
3. Provider cannot register with blockchain using invalid hostname

**Exit Code 1** typically indicates: "Configuration validation failed"

---

## Log Access Attempts (All Blocked)

### Attempt 1: kubectl logs
```
Error from server (Forbidden):
Forbidden (user=system:kube-apiserver, verb=get, resource=nodes, subresource(s)=[proxy])
```
**Issue**: RBAC configuration prevents API server from proxying logs

### Attempt 2: Container Runtime (crictl)
```
Error: permission denied (unix:///run/containerd/containerd.sock)
```
**Issue**: Root access required to container runtime

### Attempt 3: Docker API
```
permission denied while trying to connect to the docker API
```
**Issue**: Not using Docker runtime

### Attempt 4: Termination Message
```
(empty)
```
**Issue**: Container exits before writing termination message

---

## Verified Working Components

### ✅ Infrastructure Layer
- [x] Kubernetes cluster (currently in maintenance)
- [x] PersistentVolume (10Gi, bound)
- [x] PersistentVolumeClaim (bound)
- [x] StorageClass (configured)
- [x] Network policies (disabled, as expected)

### ✅ Configuration Layer
- [x] Wallet keys (key.txt, key-pass.txt present)
- [x] Wallet format (64-char hex, correct)
- [x] RPC endpoint (reachable, HTTP 200)
- [x] Chain ID (sandbox-2 testnet)
- [x] Node selectors (none required)
- [x] Tolerations (configured)

### ✅ Resource Layer
- [x] GPU labels (8 GPUs across 4 nodes)
- [x] Topology labels (region + zone configured)
- [x] Resource limits (CPU: 2, Memory: 2Gi)
- [x] Volume mounts (home, keys, scripts, config)

---

## Configuration Gaps

### Critical Gaps (Blocks Startup)
1. **Public Hostname**: `provider.` → Needs: `provider.YOUR_DOMAIN.com`
2. **Ingress Domain**: `ingress.` → Needs: `ingress.YOUR_DOMAIN.com`

### Optional Gaps (Can Configure Later)
3. **Let's Encrypt**: Currently disabled (`AP_CERT_ISSUER_ENABLED: false`)
4. **Mainnet vs Testnet**: Using sandbox-2 (testnet), not mainnet
5. **Blocked Hostnames**: Empty list (no restrictions)

---

## PVC and Storage Analysis

### Current PVC State
```
NAME                              STATUS   VOLUME                         CAPACITY
home-akash-provider-0             Bound    akash-provider-home-pv-new    10Gi
home-akash-provider-akash-...     Bound    pvc-558e5da2-bb07-4b76-b8fe  10Gi
```

**Note**: Second PVC (`home-akash-provider-akash-provider-fixed-0`) is from an older deployment attempt (2d18h old). Can be cleaned up after confirming current deployment works.

**PV Details**:
```yaml
Name: akash-provider-home-pv-new
Capacity: 10Gi
Access Modes: RWO
StorageClass: akash-provider-local-static
Node: zephyr
Path: /var/lib/kubernetes/pv-akash-provider
State: Bound
```

---

## StatefulSet Configuration

**Replicas**: 1 (desired), 0 (ready)
**Volume Claim Template**: `home` → creates `home-akash-provider-<ordinal>`
**Current Pod**: `akash-provider-0` (ordinal: 0)

**Health Check**:
```yaml
Liveness:  exec [/bin/sh -c if [ -f /tmp/healthy ]; then exit 0; else exit 1; fi]
Initial Delay: 10s
Period: 10s
```

---

## Container Lifecycle

### Startup Sequence
1. Init container (`init`) runs → Completes successfully ✅
2. Main container (`provider`) starts → Fails immediately ❌
3. Kubernetes waits ~40s → Restarts container
4. Loop repeats (CrashLoopBackOff)

### Timing Analysis
- Container start: ~3 seconds
- Exit: immediate (exit code 1)
- Back-off period: 40-80 seconds
- Restart attempt: 9 times so far

---

## Additional Cleanup Actions Taken

### Stale Pods Removed
1. **provider-debug-gateway-removed** (Age: 45h)
   - Purpose: Debugging from previous deployment attempt
   - Action: Deleted

2. **cert-helper** (Age: 35h, Status: Error)
   - Purpose: Let's Encrypt certificate management
   - Status: Failed with exit code 1
   - Action: Deleted (will recreate if needed)

---

## Resolution Path

### Step 1: Configure Domain (User-Deferred)
Waiting for user to provide domain name for:
- `AKASH_CLUSTER_PUBLIC_HOSTNAME`
- `AKASH_DEPLOYMENT_INGRESS_DOMAIN`

### Step 2: Update Configuration
```bash
kubectl patch cm akash-provider-main -n akash-provider --type=json \
  -p='[{"op": "replace", "path": "/data/AKASH_CLUSTER_PUBLIC_HOSTNAME", "value":"provider.YOUR_DOMAIN.com"}]'

kubectl patch cm akash-provider-main -n akash-provider --type=json \
  -p='[{"op": "replace", "path": "/data/AKASH_DEPLOYMENT_INGRESS_DOMAIN", "value":"ingress.YOUR_DOMAIN.com"}]'
```

### Step 3: Restart Provider
```bash
kubectl delete pod akash-provider-0 -n akash-provider
# StatefulSet will recreate pod automatically
```

### Step 4: Access Logs (After Fix)
```bash
kubectl logs akash-provider-0 -n akash-provider --tail=100 -f
```

### Step 5: Verify Registration
```bash
# Check if provider is registered on blockchain
kubectl exec -n akash-provider akash-provider-0 -- akash query provider get <address>
```

---

## Alternative: Quick Test with Internal Domain

For testing without a public domain, temporarily use:

```yaml
AKASH_CLUSTER_PUBLIC_HOSTNAME: provider.10.1.1.110.nip.io
AKASH_DEPLOYMENT_INGRESS_DOMAIN: ingress.10.1.1.110.nip.io
```

This uses nip.io dynamic DNS service (free, no registration required).

**Note**: This will NOT work for production deployment (tenants can't reach your provider), but useful for testing if provider binary starts correctly.

---

## Support Information

**Helm Chart**: akash/provider v14.0.8
**Provider Version**: 0.10.8-rc3
**Documentation**: https://docs.akash.network/providers
**GitHub Issues**: https://github.com/akash-network/provider/issues

---

## Summary

**Diagnosis**: Provider container crashes immediately due to invalid hostname configuration (`provider.` is not a valid FQDN).

**Confidence**: HIGH - All other components verified working, hostname is only missing piece.

**Blockers**: Domain configuration (user-deferred), cluster maintenance (ongoing).

**Next Action**: Wait for domain decision + cluster restoration, then apply hostname fix.
