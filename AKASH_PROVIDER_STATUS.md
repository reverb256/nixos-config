# Akash Provider Deployment Status
**Generated**: 2026-03-18 04:38 UTC
**Agent**: Claude Code (Systematic Debugging)

## Summary
Akash provider deployment has been audited. Critical issues identified that prevent provider from starting.

## Completed Tasks ✅

### Task 1: Fix Akash Provider Storage (PV/PVC Binding)
**Status**: ✅ COMPLETED
**Issue**: PVC `home-akash-provider-0` stuck in Pending state for 27 hours
**Root Cause**: PV `akash-provider-home-pv-new` in "Released" state with old claimRef
**Fix Applied**:
```bash
kubectl patch pv akash-provider-home-pv-new -p '{"spec":{"claimRef":null}}'
```
**Result**: PVC successfully bound to PV

### Task 2: Label GPU Nodes for Akash Visibility
**Status**: ✅ COMPLETED
**Finding**: GPU nodes already labeled correctly by `akash-node-labels.service`
**Verified Labels**:
- **forge**: rtx4060 + rx5700xt (2x NVIDIA + 2x AMD)
- **nexus**: rtx3060ti (1x NVIDIA)
- **sentry**: rx5600xt (1x AMD)
- **zephyr**: rtx3090 + rtx3060ti (2x NVIDIA)
**Total**: 8 GPUs across 4 nodes
**Note**: Service only runs on zephyr; needs deployment to other nodes

## Pending Tasks ⏳

### Task 3: Configure Akash Provider Domain (BLOCKED)
**Status**: ⏸️ BLOCKED - Cluster maintenance in progress
**Critical Issue**: `AKASH_CLUSTER_PUBLIC_HOSTNAME: provider.` is incomplete
**Impact**: Provider container crashes immediately (exit code 1)
**Required Fix**:
- Set valid public hostname (e.g., `provider.example.com`)
- Configure Cloudflare Tunnel or DNS record
- Update ConfigMap: `akash-provider-main`
- Related: `AKASH_DEPLOYMENT_INGRESS_DOMAIN: ingress.` also incomplete

**Current Configuration**:
```yaml
AKASH_CLUSTER_PUBLIC_HOSTNAME: provider.
AKASH_DEPLOYMENT_INGRESS_DOMAIN: ingress.
AKASH_CHAIN_ID: sandbox-2  # Using testnet, not mainnet
AP_CERT_ISSUER_ENABLED: false  # Let's Encrypt disabled
```

### Task 4: Add Region/Zone Topology Labels (PARTIAL)
**Status**: ⚠️ PARTIAL COMPLETE
**Current State**:
- All nodes: `topology.kubernetes.io/region=us-west` ✅
- zephyr only: `topology.kubernetes.io/zone=homelab`
- **Missing**: forge, nexus, sentry zone labels

**Issue**: `akash-node-labels.service` only enabled on zephyr
**Fix Required**: Deploy module to all nodes or label manually

### Task 5: Verify and Test Akash Provider Deployment (BLOCKED)
**Status**: ⏸️ BLOCKED - Cluster maintenance in progress
**Blockers**:
1. Kubernetes API server down (deactivating stop-sigterm)
2. Control plane services inactive (controller-manager, proxy, scheduler)
3. Cannot access logs or modify ConfigMaps until cluster restored

## Container Crash Analysis

### Symptom
Provider container exits with code 1 after ~3 seconds, repeated BackOff restarts

### Attempted Diagnostics
- ❌ kubectl logs blocked by RBAC: `Forbidden (user=system:kube-apiserver, verb=get, resource=nodes, subresource(s)=[proxy])`
- ❌ crictl logs blocked by permissions
- ❌ Docker daemon access denied
- ⏸️ Termination message empty

### Root Cause (Inferred)
Incomplete hostname configuration (`provider.`) prevents provider from:
- Registering with blockchain network
- Receiving bids from tenants
- Establishing ingress routes

## Next Actions (Once Cluster Restored)

1. **Configure Domain** (Critical):
   ```bash
   # Get valid hostname from user
   kubectl patch cm akash-provider-main -n akash-provider --type=json \
     -p='[{"op": "replace", "path": "/data/AKASH_CLUSTER_PUBLIC_HOSTNAME", "value":"provider.YOUR_DOMAIN.com"}]'
   ```

2. **Fix Zone Labels**:
   ```bash
   kubectl label node forge topology.kubernetes.io/zone=homelab --overwrite
   kubectl label node nexus topology.kubernetes.io/zone=homelab --overwrite
   kubectl label node sentry topology.kubernetes.io/zone=homelab --overwrite
   ```

3. **Access Logs**:
   ```bash
   kubectl logs akash-provider-0 -n akash-provider --tail=100
   ```

4. **Consider Switching to Mainnet**:
   - Current: `sandbox-2` (testnet)
   - Mainnet: `akashnet-2`
   - Update ConfigMap if deploying to production

## Infrastructure Notes

### GPU Inventory
- **Total**: 8 GPUs
- **NVIDIA**: 5x (RTX 3090, RTX 3060 Ti, RTX 3060 Ti, RTX 4060, RTX 4060)
- **AMD**: 3x (RX 5700 XT, RX 5700 XT, RX 5600 XT)

### Storage
- **PV**: `akash-provider-home-pv-new` (10Gi, local, Zephyr)
- **PVC**: `home-akash-provider-0` (Bound ✅)
- **StorageClass**: `akash-provider-local-static` (WaitForFirstConsumer)

### Network
- **Namespace**: `akash-provider`
- **Pod**: `akash-provider-0` (scheduled to zephyr)
- **Image**: `ghcr.io/akash-network/provider:0.10.8-rc3`

## Related Configuration Files
- `/etc/nixos/modules/services/akash-provider.nix` - Module definition
- `/etc/nixos/modules/services/cloudflared.nix` - Cloudflare Tunnel (exists, not configured)
- `/etc/nixos/secrets/cloudflared-token.age` - Encrypted tunnel token

## Dependencies
- Kubernetes cluster (currently down for maintenance)
- Wallet key secret: `akash-provider-keys-new` ✅
- GPU node labels ✅
- Valid public hostname ❌
- Ingress controller deployment status: UNKNOWN

---
**Notes for Next Agent**: Cluster is undergoing maintenance by another agent working on Forge boot issues. Wait for cluster restoration before proceeding with Task 3 (domain configuration).
