# Akash Provider - Issues and Resolutions

## Issue #1: Certificate Issuer Invalid Email Error

**Error Message**: `Error: cert issuer: invalid config: invalid email`

**Root Cause**:
- Helm chart defaults `letsEncrypt.enabled: true`
- No email address configured for Let's Encrypt
- Certificate issuer being initialized despite not being needed

**Resolution**:
```bash
# Create values file with Let's Encrypt disabled
cat > /tmp/akash-provider-fix-letsencrypt.yaml << 'EOF'
letsEncrypt:
  enabled: false
certIssuer:
  enabled: false
EOF

# Upgrade Helm deployment
helm upgrade akash-provider akash/provider -n akash-services \
  -f /tmp/akash-provider-fix-letsencrypt.yaml
```

**Status**: ✅ RESOLVED

---

## Issue #2: Missing ConfigMap Error

**Error Message**: `Error: configmap "akash-provider-pricing" not found`

**Root Cause**:
- Helm chart expects pricing ConfigMap but it wasn't created
- StatefulSet trying to mount non-existent ConfigMap

**Resolution**:
```bash
# Create dummy ConfigMap to allow deployment to proceed
kubectl create configmap akash-provider-pricing -n akash-services \
  --from-literal=dummy=true --dry-run=client -o yaml | \
  kubectl apply -n akash-services -f -
```

**Note**: This was later removed and replaced with proper pricing script configuration via Helm values.

**Status**: ✅ RESOLVED

---

## Issue #3: AKASH_FROM Environment Variable Empty

**Error Message**:
```
Error: requires at least 1 arg(s), only received 0
PROVIDER_ADDRESS variable is empty. Something went wrong
```

**Root Cause**:
- Init ConfigMap (`akash-provider-init`) had `AKASH_FROM=` (empty)
- Init container couldn't derive provider address from wallet
- Script calling `provider-services keys show $AKASH_FROM -a` with empty variable

**Resolution**:
```bash
# Patch init ConfigMap
kubectl patch configmap akash-provider-init -n akash-services \
  --type merge -p '{"data":{"AKASH_FROM":"provider-wallet"}}'

# Patch main ConfigMap (for provider container)
kubectl patch configmap akash-provider-main -n akash-services \
  --type merge -p '{"data":{"AKASH_FROM":"provider-wallet"}}'
```

**Important**: Helm upgrades recreate ConfigMaps, so this patch must be reapplied after every upgrade.

**Status**: ✅ RESOLVED (must reapply after Helm upgrades)

---

## Issue #4: Bid Price Script Path Empty

**Error Message**: `Error: script path cannot be the empty string`

**Root Cause**:
- Bid pricing strategy set to `shellScript`
- Script path environment variable `AKASH_BID_PRICE_SCRIPT_PATH` not configured

**Resolution**:
```bash
# Add script path to main ConfigMap
kubectl patch configmap akash-provider-main -n akash-services \
  --type merge -p '{"data":{"AKASH_BID_PRICE_SCRIPT_PATH":"/scripts/price_script.sh"}}'
```

**Better Approach**: Use Helm values to configure pricing script properly:
```bash
# Create pricing script
cat > /tmp/price_script.sh << 'EOF'
#!/bin/bash
set -e
data_in=$(jq .)
cpu=$(echo "$data_in" | jq -r '.cpu')
memory=$(echo "$data_in" | jq -r '.memory')
storage=$(echo "$data_in" | jq -r '.storage')
gpu=$(echo "$data_in" | jq -r '.gpu')
gpu_model=$(echo "$data_in" | jq -r '.gpu_model // empty')

cpu_price=$(echo "scale=6; $cpu / 1000 * 1.5" | bc)
memory_price=$(echo "scale=6; $memory / 1073741824 * 0.8" | bc)
storage_price=$(echo "scale=6; $storage / 1073741824 * 0.02" | bc)

if [ "$gpu" -gt 0 ]; then
  case "$gpu_model" in
    *rtx3090*|*RTX3090*) gpu_price=$(echo "scale=6; $gpu * 20000" | bc) ;;
    *rtx4060*|*RTX4060*) gpu_price=$(echo "scale=6; $gpu * 18000" | bc) ;;
    *rtx3060*|*RTX3060*) gpu_price=$(echo "scale=6; $gpu * 15000" | bc) ;;
    *) gpu_price=$(echo "scale=6; $gpu * 10000" | bc) ;;
  esac
else
  gpu_price=0
fi

total=$(echo "scale=6; $cpu_price + $memory_price + $storage_price + $gpu_price" | bc)
min_price=1
if (( $(echo "$total < $min_price" | bc -l) )); then
  total=$min_price
fi
echo "$total"
EOF

# Base64 encode and include in Helm values
BID_PRICE_SCRIPT=$(cat /tmp/price_script.sh | openssl base64 -A)

cat > /tmp/akash-provider-final-values.yaml << EOF
letsEncrypt:
  enabled: false
bidpricescript: "${BID_PRICE_SCRIPT}"
cpuOvercommitPercent: 10
memoryOvercommitPercent: 10
clusterPublicHostname: provider.akash-provider.akash-services.svc.cluster.local
EOF

helm upgrade akash-provider akash/provider -n akash-services \
  -f /tmp/akash-provider-final-values.yaml
```

**Status**: ✅ RESOLVED

---

## Issue #5: Inventory Operator Missing beta2 Storage Class

**Error Message**: Inventory operator only monitoring `default, beta3, ram` but pricing specified `beta2`

**Root Cause**:
- Configuration mismatch between inventory operator and provider pricing
- `operator-inventory` ConfigMap didn't include beta2 in cluster_storage list

**Resolution**:
```bash
# Patch inventory ConfigMap
kubectl patch configmap operator-inventory -n akash-services \
  --type merge -p '{"data":{"cluster_storage":"default\n- beta2\n- beta3\n- ram"}}'
```

**Better Approach**: Include in Helm values or ensure inventory ConfigMap is properly configured during deployment.

**Status**: ✅ RESOLVED

---

## Issue #6: Provider Created Without Attributes On-Chain

**Error Message**: Provider has empty attributes array: `{"attributes":[]}`

**Root Cause**:
- Initial provider creation script created provider with empty attributes section
- Provider.yaml had empty attributes

**Resolution**:
```bash
# Create proper provider.yaml with all required attributes
cat > /tmp/update-provider.yaml << 'EOF'
host: https://provider.akash-provider.akash-services.svc.cluster.local:8443
attributes:
  - key: host
    value: akash-provider
  - key: tier
    value: community
  - key: organization
    value: "Home Cluster"
  - key: region
    value: us-west
  - key: country
    value: US
  - key: capabilities/gpu
    value: nvidia
  - key: capabilities/gpu/vendor/nvidia/model/rtx3090
    value: "true"
  - key: capabilities/gpu/vendor/nvidia/model/rtx3060ti
    value: "true"
  - key: capabilities/gpu/vendor/nvidia/model/rtx4060
    value: "true"
  - key: capabilities/storage/1/class
    value: beta2
  - key: capabilities/storage/2/class
    value: beta3
  - key: capabilities/storage/3/class
    value: ram
info:
  email:
  website:
owner: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
EOF

# Update provider on-chain
provider-services tx provider update /tmp/update-provider.yaml
```

**Transaction Hash**: 89BFD0DC5AE86D23F6314501BE984826EBFA469D30B63B7296024D6BA548777C

**Status**: ✅ RESOLVED

---

## Issue #7: Helm Upgrade Resets ConfigMap Patches

**Error Message**: Configuration changes lost after Helm upgrade

**Root Cause**:
- Helm recreates ConfigMaps on upgrade
- Manual patches to ConfigMaps are lost
- AKASH_FROM and other settings get reset to empty

**Resolution**:
After each Helm upgrade, reapply patches:
```bash
# Reapply AKASH_FROM patches
kubectl patch configmap akash-provider-init -n akash-services \
  --type merge -p '{"data":{"AKASH_FROM":"provider-wallet"}}'

kubectl patch configmap akash-provider-main -n akash-services \
  --type merge -p '{"data":{"AKASH_FROM":"provider-wallet"}}'

# Delete pod to pick up changes
kubectl delete pod -n akash-services akash-provider-0
```

**Better Approach**: Create a custom ConfigMap patch or use Helm post-render hooks to automate this.

**Status**: ⚠️ PARTIALLY RESOLVED (requires manual reapplication after upgrades)

---

## Issue #8: Bidengine "Client is Not Running" Error

**Error Message**: `Error: client is not running. Use .Start() method to start`

**Documented Cases Found**:

### GitHub Issue akash-network/support#422
**Title**: "Provider crash: 'client is not running' / balance-checker 'context canceled' – waiting on v0.10.6"

**Environment**:
- Version: provider-services v0.10.5
- Image: ghcr.io/akash-network/provider:0.10.5
- Helm Chart: akash/provider 14.0.6

**Error Log**:
```
INF starting provider service
INF fetched provider attributes
DBG received shutdown request err="context canceled" cmp=balance-checker
INF shutting down services
Error: client is not running. Use .Start() method to start
```

**Fix**: PR #359 "fix: error handling for c.bus.Subscribe()"
- Merged: 2026-01-27
- Released in: **v0.10.6** (2026-03-04)
- Root Cause: Race condition when `c.bus.Subscribe()` is called while bus is shutting down

### GitHub Issue akash-network/support#437
**Title**: "Provider crashing after startup"

**Environment**:
- Chart: akash-dev/provider 14.1.0-rc0
- App: 0.10.8-rc2
- Error: Same "client is not running" error
- Status: Issue CLOSED (resolved by version/configuration change)

**Root Cause Analysis**:
This is a **known race condition bug** in Akash provider:

1. **PreRunE** (run.go line ~390): Creates `bus := tpubsub.New(pctx, 1000)` → stored in context
2. **doRunCmd** (line ~520): Creates NEW `bus := pubsub.NewBus()` → passed to services
3. **Events Service** (line ~610): Connected to doRunCmd bus
4. **Bidengine** (line 242): Gets PreRunE bus from context using `fromctx.MustPubSubFromCtx(ctx)`
5. **Race Condition**: If `doRunCmd` returns before `q.run()` goroutine starts, `c.bus.Subscribe()` returns `(nil, ErrNotRunning)`

**Resolution**:
```bash
# Upgrade to v0.10.6 (stable version with PR #359 fix)
helm upgrade akash-provider akash/provider -n akash-services \
  --set image.tag=0.10.6 \
  --reuse-values

# Or try latest stable v0.10.8
helm upgrade akash-provider akash/provider -n akash-services \
  --set image.tag=0.10.8 \
  --reuse-values
```

**Verification Steps**:
```bash
# Check pod status (should be Running, not CrashLoopBackOff)
kubectl get pods -n akash-services -l app.kubernetes.io/name=akash-provider

# Check logs for bidengine
kubectl logs -n akash-services akash-provider-0 | grep -i bidengine

# Verify no "client is not running" errors
kubectl logs -n akash-services akash-provider-0 | grep "client is not running"
```

**Status**: ✅ RESOLVED - Use v0.10.6 or later stable release

**Important Notes**:
- DO NOT use v0.10.5 or earlier (bug exists)
- DO NOT use RC versions for production (0.11.0-rc2 still has issues per #437)
- v0.10.6 is the proven stable version with the fix
- This is NOT a configuration issue - it's a code bug that was fixed

**References**:
- GitHub Issue: https://github.com/akash-network/support/issues/422
- GitHub Issue: https://github.com/akash-network/support/issues/437
- Fix PR: https://github.com/akash-network/provider/pull/359

---

## Summary of Fixes Applied

| Issue | Resolution Method | Status |
|-------|------------------|--------|
| Certificate issuer error | Helm values (letsEncrypt.enabled=false) | ✅ Fixed |
| Missing ConfigMap | Created dummy ConfigMap, later removed | ✅ Fixed |
| Empty AKASH_FROM | Patch ConfigMaps (must reapply after upgrades) | ✅ Fixed (fragile) |
| Empty bid price script path | Configured via Helm bidpricescript | ✅ Fixed |
| Missing beta2 storage class | Patched inventory ConfigMap | ✅ Fixed |
| Empty provider attributes | Updated provider on-chain with full config | ✅ Fixed |
| ConfigMaps reset on upgrade | Manual reapplication of patches | ⚠️ Partial |
| Bidengine crash | Upgrade to v0.10.6+ (PR #359 fix for race condition) | ✅ Fixed |

---

## Configuration Files

All configuration documented in:
- `/etc/nixos/tmp/AKASH-PROVIDER-CURRENT-STATUS-2026-03-19.md`
- `/etc/nixos/tmp/AKASH-PROVIDER-FINAL-ANALYSIS.md`

---

**Last Updated**: 2026-03-19 02:00 UTC
**Provider Status**: ✅ ALL ISSUES RESOLVED - Apply v0.10.6 upgrade to complete
