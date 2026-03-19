# Akash Provider Fixes - 2026-03-19

## Current Status

### ✅ Working Components
- Wallet registered: `akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6`
- Certificate valid on-chain (serial: 189E1B2C59B6BFF3)
- Init container successfully updates provider
- Hardware discovery pods running on all 4 nodes
- GPU node labels applied correctly
- Storage classes configured

### ❌ Issues to Fix

1. **Provider Container CrashLoopBackOff**
   - Error: "client is not running. Use .Start() method to start"
   - Root cause: Provider starts before inventory operator is fully ready

2. **Missing RBAC Permissions**
   - Inventory operator can't watch PersistentVolumes
   - Missing `create` permission for discovery pods (seems to have recovered)

---

## Fix #1: Add RBAC Permissions

### Quick Fix (kubectl patch)
```bash
# Add PersistentVolume permissions to existing ClusterRole
kubectl patch clusterrole akash-operator-inventory-hardware-discovery --type='json' -p='[
  {
    "op": "add",
    "path": "/rules/-",
    "value": {
      "apiGroups": [""],
      "resources": ["persistentvolumes", "persistentvolumeclaims"],
      "verbs": ["get", "list", "watch"]
    }
  },
  {
    "op": "add",
    "path": "/rules/-",
    "value": {
      "apiGroups": ["storage.k8s.io"],
      "resources": ["storageclasses"],
      "verbs": ["get", "list", "watch"]
    }
  }
]'

# Add pod create/delete/update permissions
kubectl patch clusterrole akash-operator-inventory-hardware-discovery --type='json' -p='[
  {
    "op": "replace",
    "path": "/rules/1/verbs",
    "value": ["get", "list", "watch", "create", "delete", "update"]
  }
]'
```

---

## Fix #2: Fix Provider Startup Timing

### Option A: Enable Readiness Probe (Recommended)
```bash
helm upgrade akash-provider akash/provider \
  --namespace akash-services \
  --set readinessProbe.enabled=true \
  --set readinessProbe.initialDelaySeconds=30 \
  --set readinessProbe.periodSeconds=10 \
  --reuse-values
```

### Option B: Increase Startup Delay
```bash
helm upgrade akash-provider akash/provider \
  --namespace akash-services \
  --set startupProbe.enabled=true \
  --set startupProbe.initialDelaySeconds=60 \
  --set startupProbe.periodSeconds=10 \
  --set startupProbe.failureThreshold=30 \
  --reuse-values
```

---

## Fix #3: Verify Wallet Balance

You mentioned having 30 AKT. Let's verify:

```bash
# Using a public RPC endpoint
curl -s "https://akash.dev33.io/api/v1/account/akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6" | jq '.'

# Or use the Akash Console
# Visit: https://console.akash.network
# Connect your wallet and check the balance
```

**Minimum recommended balance:**
- 5 AKT for registration fees (already spent)
- 10-20 AKT for bid deposits and operations
- **Total: 15-25 AKT minimum**

If you have 30 AKT, you're in good shape!

---

## Fix #4: Restart Provider After RBAC Fix

```bash
# Delete the provider pod to restart with new permissions
kubectl delete pod -n akash-services akash-provider-0

# Watch the logs
kubectl logs -n akash-services akash-provider-0 -f
```

---

## Verification Steps

### 1. Check Inventory Operator
```bash
# Should see no "Unauthorized" errors
kubectl logs -n akash-services deployment/operator-inventory --tail=20

# Check if hardware is discovered
kubectl get inventory -n akash-services
```

### 2. Check Provider Status
```bash
# Provider should be Running (not CrashLoopBackOff)
kubectl get pods -n akash-services | grep provider

# Check provider logs for successful startup
kubectl logs -n akash-services akash-provider-0 --tail=50
```

### 3. Verify Provider On-Chain
```bash
# Using Akash CLI (if available) or the Console API
curl -s "https://api.akash.net/api/v2/provider/info?address=akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6" | jq '.'
```

### 4. Test Bidding
```bash
# Check if provider is actively bidding
kubectl logs -n akash-services akash-provider-0 | grep -i "bid\|lease"

# Query active leases
curl -s "https://api.akash.net/api/v2/leases?owner=akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6" | jq '.'
```

---

## Expected Results After Fixes

✅ **Inventory Operator:**
- No more "Unauthorized" errors
- Successfully discovers GPUs on all nodes
- Reports hardware inventory to provider

✅ **Provider Container:**
- Starts successfully and stays running
- Connects to inventory service
- Ready to bid on leases

✅ **Provider Operations:**
- Bids on GPU workloads
- Wins leases based on your pricing
- Earns AKT from deployed workloads

---

## Pricing Review

Your current pricing (uakt per block):
- RTX 3090: 20,000 (~$8.70/month at 50% util)
- RTX 4060: 18,000 (~$7.80/month)
- RTX 3060 Ti: 15,000 (~$6.50/month)

**Potential monthly earnings (at 50% utilization):**
- 2x RTX 3090 (zephyr): ~$17.40
- 1x RTX 3060 Ti (nexus): ~$6.50
- 2x RTX 4060 (forge): ~$15.60
- **Total: ~$40/month**

**Note:** These are estimates. Actual earnings depend on:
- Network demand
- Your pricing competitiveness
- Lease winning rate
- Actual utilization

---

## Next Steps

1. **Immediate (Do Now):**
   - Apply RBAC fix (Fix #1)
   - Restart provider pod
   - Verify no more errors

2. **Short-term (Today):**
   - Verify wallet balance has 30 AKT
   - Check provider is bidding on leases
   - Monitor logs for 24 hours

3. **Long-term (This Week):**
   - Adjust pricing based on demand
   - Monitor earnings via Console or API
   - Consider adding more GPUs if utilization is high

---

## Troubleshooting

### If Provider Still Crashes

```bash
# Check inventory service health
kubectl exec -n akash-services akash-provider-0 -- curl -s http://operator-inventory:8081/health

# Check if provider can reach inventory
kubectl logs -n akash-services akash-provider-0 | grep -i "inventory\|dial"

# Increase startup delay further
helm upgrade akash-provider akash/provider \
  --namespace akash-services \
  --set startupProbe.initialDelaySeconds=120 \
  --reuse-values
```

### If No Bids Are Won

```bash
# Check pricing competitiveness
curl -s "https://api.akash.net/api/v2/providers" | jq '.[] | select(.owner=="akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6")'

# Lower prices if needed
# Edit hosts/zephyr/configuration.nix
# Adjust pricing.rtx3090, rtx4060, rtx3060ti values
# Rebuild and redeploy
```

---

## Context7 Resources

For more details, I've queried the Akash documentation:
- Provider setup: `/akash-network/provider`
- Main docs: `/websites/akash_network`
- CLI commands and troubleshooting examples available

Let me know if you want me to apply any of these fixes or need more details on any step!
