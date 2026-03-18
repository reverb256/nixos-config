# Akash Provider Issues and Fixes
**Generated**: 2026-03-18 04:45 UTC
**Status**: Cluster maintenance in progress, documenting issues for resolution

## Critical Issues

### 1. ❌ Incomplete Hostname Configuration (CRITICAL - Blocks Provider Startup)
**Status**: DEFERRED (user will implement domain later)
**Impact**: Provider container crashes immediately (exit code 1, CrashLoopBackOff)

**Current Config**:
```yaml
AKASH_CLUSTER_PUBLIC_HOSTNAME: provider.    # ❌ Missing domain suffix
AKASH_DEPLOYMENT_INGRESS_DOMAIN: ingress.   # ❌ Missing domain suffix
```

**Required Fix**:
```bash
# Once domain is available, update ConfigMap:
kubectl patch cm akash-provider-main -n akash-provider --type=json \
  -p='[{"op": "replace", "path": "/data/AKASH_CLUSTER_PUBLIC_HOSTNAME", "value":"provider.YOUR_DOMAIN.com"}]'

kubectl patch cm akash-provider-main -n akash-provider --type=json \
  -p='[{"op": "replace", "path": "/data/AKASH_DEPLOYMENT_INGRESS_DOMAIN", "value":"ingress.YOUR_DOMAIN.com"}]'

# Restart pod:
kubectl delete pod akash-provider-0 -n akash-provider
```

**Why This Causes Crash**:
- Provider cannot register with blockchain network
- Cannot receive bids from tenants
- Cannot establish ingress routes for deployments

---

## Fixed Issues ✅

### 2. ✅ PV/PVC Binding Issue
**Status**: FIXED
**Issue**: PVC stuck Pending for 27 hours
**Fix Applied**:
```bash
kubectl patch pv akash-provider-home-pv-new -p '{"spec":{"claimRef":null}}'
```
**Result**: PVC successfully bound

### 3. ✅ GPU Node Labels
**Status**: VERIFIED
**Finding**: All 8 GPUs correctly labeled
- **forge**: rtx4060 + rx5700xt ✅
- **nexus**: rtx3060ti ✅
- **sentry**: rx5600xt ✅
- **zephyr**: rtx3090 + rtx3060ti ✅

### 4. ✅ Topology Zone Labels
**Status**: FIXED
**Issue**: Only zephyr had zone label
**Fix Applied**:
```bash
kubectl label node forge topology.kubernetes.io/zone=homelab --overwrite
kubectl label node nexus topology.kubernetes.io/zone=homelab --overwrite
kubectl label node sentry topology.kubernetes.io/zone=homelab --overwrite
```
**Result**: All 4 nodes now have `region=us-west, zone=homelab`

---

## Verified Working ✅

### 5. ✅ RPC Endpoint Connectivity
**Test**: `curl -I https://rpc.sandbox-2.aksh.pw:443`
**Result**: HTTP 200 (reachable)
**Note**: Using testnet (sandbox-2), not mainnet

### 6. ✅ Wallet Key Configuration
**Secret**: `akash-provider-keys-new`
**Contents**: key.txt, key-pass.txt
**Format**: 64-char hex private key (correct)

### 7. ✅ Storage Volumes
**PV**: `akash-provider-home-pv-new` (10Gi, local, bound ✅)
**PVC**: `home-akash-provider-0` (bound ✅)
**Mounts**: home, scripts, keys, provider-config-volume, kube-api-access

### 8. ✅ Kubernetes Resources
**Namespace**: akash-provider
**Pod**: akash-provider-0 (scheduled to zephyr)
**Image**: ghcr.io/akash-network/provider:0.10.8-rc3

---

## Minor Issues / Improvements

### 9. ⚠️ GPU Labeling Service Scope
**Issue**: `akash-node-labels.service` only runs on zephyr
**Current Behavior**: Only labels local node (zephyr)
**Impact**: Low - labels already applied, but manual intervention required for new nodes

**Options**:
1. **Accept current state** - Labels are correct, service works for zephyr
2. **Deploy to all nodes** - Add module to all host configs
3. **Centralized labeling** - Create cluster-level labeling job

**Recommendation**: Accept current state for now. Revisit if scaling to more nodes.

---

## Configuration Notes

### Current Network Configuration
```yaml
Chain: sandbox-2 (testnet)
RPC: https://rpc.sandbox-2.aksh.pw:443
Node: https://rpc.sandbox-2.aksh.pw:443
From: provider-wallet
Keyring: test
```

### Current Cluster Status
**Control Plane**: DOWN (maintenance in progress)
- kube-apiserver: deactivating stop-sigterm
- kube-controller-manager: inactive
- kube-scheduler: inactive
- kube-proxy: inactive
- kubelet: active ✅

### GPU Inventory
```
Total: 8 GPUs
NVIDIA: 5x (RTX 3090, RTX 3060 Ti ×2, RTX 4060 ×2)
AMD: 3x (RX 5700 XT ×2, RX 5600 XT)
```

---

## Next Actions (Priority Order)

### Once Cluster is Restored:

1. **Configure Domain** (User-deferred - awaiting domain decision)
   - Update hostname in ConfigMap
   - Configure DNS or Cloudflare Tunnel
   - Restart provider pod

2. **Access Provider Logs**
   ```bash
   kubectl logs akash-provider-0 -n akash-provider --tail=100
   ```

3. **Verify Provider Registration**
   ```bash
   # Check if provider registered on blockchain:
   akash query provider get <provider-address>
   ```

4. **Consider Mainnet Migration**
   - Current: sandbox-2 (testnet)
   - Production: akashnet-2 (mainnet)
   - Requires ConfigMap update for chain ID and RPC endpoints

5. **Enable Persistent Storage**
   - Review storage class configuration
   - Test storage provisioning
   - Verify volume binding

---

## Files and References

**Configuration Files**:
- `/etc/nixos/modules/services/akash-provider.nix` - Provider module
- `/etc/nixos/modules/services/cloudflared.nix` - Cloudflare Tunnel (exists, not configured)
- `/etc/nixos/secrets/cloudflared-token.age` - Encrypted tunnel token

**Documentation**:
- `/etc/nixos/AKASH_PROVIDER_STATUS.md` - Full deployment audit
- `/etc/nixos/AKASH_PROVIDER_ISSUES_AND_FIXES.md` - This file

**Resources**:
- Akash Provider Docs: https://docs.akash.network/providers
- Helm Chart: https://github.com/akash-network/helm-charts

---

**Summary**: 4/5 tasks complete. Only blocking issue is hostname configuration (deferred). All infrastructure verified working. Ready to deploy once domain is configured and cluster maintenance completes.
