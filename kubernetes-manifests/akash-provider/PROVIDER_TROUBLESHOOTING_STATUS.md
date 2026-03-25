# Akash Provider Troubleshooting Status

**Date:** 2026-03-24 22:15 UTC
**Provider Version:** v0.11.0 (chart 15.0.0)
**Helm Revision:** 46
**Status:** ❌ CrashLoopBackOff - Bidengine failing to start

---

## Error Summary

**Primary Error:** `Error: client is not running. Use .Start() method to start`

**Module:** bidengine service
**Error Context:** "context canceled"
**Timing:** Occurs immediately after successful provider initialization

**Log Sequence:**
```
[3:10AM] INF starting provider service
[3:10AM] INF starting with existing reservations (qty: 0)
[3:10AM] INF grpc listening on "0.0.0.0:8444"
[3:10AM] ERR bidengine service terminated with error (err="context canceled")
Error: client is not running. Use .Start() method to start
[3:10AM] INF shutting down services
```

---

## Fixes Applied

### ✅ Memory Limits (Fixed)
**Issue:** Pod rejected by LimitRange (max 2Gi per container)
**Solution:** Reduced from 4Gi → 2Gi
**Status:** Resolved - pods now create successfully

### ✅ Withdrawal Period (Fixed)
**Issue:** `AKASH_WITHDRAWAL_PERIOD: 1h` causing withdrawal goroutine crash
**Solution:** Set `withdrawalperiod: ""` in Helm values
**Implementation:**
```yaml
# CRITICAL: Empty withdrawal period disables periodic withdrawals
withdrawalperiod: ""
```
**Status:** Resolved - ConfigMap now shows empty value

### ✅ Inventory Configuration (Added)
**Issue:** Missing beta2 storage class (fast NVMe SSD)
**Solution:** Added inventory operator configuration
**Implementation:**
```yaml
inventory:
  config:
    version: v1
    cluster_storage:
      - beta2    # NVMe SSD
      - beta3    # HDD
      - ram      # RAM disk
    exclude:
      nodes:
        - ^zephyr.*  # Exclude control plane node
      node_storage: []
```
**Status:** Applied - inventory operator configured

### ✅ Environment Variables (Corrected)
**Issue:** Wrong syntax for environment variables
**Solution:** Using `env:` for shared vars (not `extraEnvs:`)
**Status:** Corrected in values file

---

## Current Configuration

### Helm Release
```bash
helm list -n akash-services
NAME                     REVISION UPDATED                   STATUS
akash-provider           46       2026-03-24 22:09:27 UTC   deployed
```

### ConfigMap Verification
```bash
kubectl get configmap akash-provider-main -n akash-services
AKASH_WITHDRAWAL_PERIOD: ""  ✅ Empty (correct)
```

### Pod Status
```bash
kubectl get pods -n akash-services -l app=akash-provider
NAME               READY   STATUS             RESTARTS   AGE
akash-provider-0   0/1     Error              5          3m39s
```

---

## Investigation Findings

### Git History Analysis
- **Commit b7c239c:** "comprehensive Calico CNI and provider configuration fixes"
  - File shows `tag: "0.11.0"`
  - Commit message mentions "Downgraded provider from v0.11.0 to v0.10.7"
  - ⚠️ **Discrepancy:** Commit message contradicts file content

### Working Commit Analysis
The working commit (740804b) is actually about etcd HA migration, not Akash provider.
The actual working provider configuration is from commit b7c239c.

### Key Differences in Working Configuration
1. **Custom run.sh script:** Builds provider command with cert issuer flags
2. **Complex refresh_provider_cert.sh:** Full CSR generation and blockchain submission
3. **Simplified init.sh:** No create_provider.sh call, just wait_for_rpc

---

## Latest Updates (2026-03-25 16:20 UTC)

### ✅ DNS Trailing Dot Bug - ROOT CAUSE IDENTIFIED IN PROVIDER CODE
**Bug Location:** `cluster/util/service_discovery_agent.go:167-169`
**Issue:** DNS SRV lookup returns FQDN with trailing dot; code doesn't strip it before HTTP URL construction
**Malformed URL:** `http://operator-hostname.akash-services.svc.cluster.local.:8080/health`

**✅ WORKAROUND APPLIED:** Static endpoint configuration
- **Flag:** `--hostname-operator-endpoint=10.244.169.20:8080`
- **Method:** Updated ConfigMap `akash-provider-script` with custom run.sh
- **Result:** ✅ DNS discovery bypassed, health check succeeds (status=200)
- **Logs show:**
  ```
  DBG using manually configured endpoint host=10.244.169.20 port=8080 service=hostname-operator
  INF check result operator=hostname status=200
  INF all waitables ready
  INF grpc listening on "0.0.0.0:8444"
  ```

### ❌ NEW BLOCKER: Balance checker immediate shutdown after gRPC starts
**Current State:** Provider starts successfully but crashes immediately after gRPC server starts
**Error:** "client is not running. Use .Start() method to start"
**Timing:** Occurs after:
1. ✅ Certificate validation passes
2. ✅ All migrations checked
3. ✅ Hostname operator health check succeeds (200 OK)
4. ✅ Inventory operator connects
5. ✅ gRPC server starts on port 8444
6. ❌ Balance checker receives "context canceled" shutdown request
7. ❌ Provider exits with "client is not running" error

**Log Sequence:**
```
[8:30AM] INF grpc listening on "0.0.0.0:8444"
[8:30AM] DBG received shutdown request cmp=balance-checker err="context canceled" module=provider-service
[8:30AM] DBG shutdown complete cmp=balance-checker module=provider-service
Error: client is not running. Use .Start() method to start
```

**Root Cause Analysis:**
- **PRIMARY ISSUE:** Balance checker (`balance_checker.go:133`) calls `bc.session.Client().Node().SyncInfo(ctx)` immediately after startup
- **SECONDARY ISSUE:** The main provider context is being canceled almost immediately after gRPC starts
- **TRIGGER:** One of the core services (cluster, bidengine, or manifest) is terminating immediately, causing the provider context to cancel
- **TIMING:** Balance checker hasn't even performed its first blockchain sync check when context is canceled

**Investigation Status:**
- ✅ DNS trailing dot bug confirmed and worked around
- ✅ Static endpoint workaround applied and verified (hostname operator health check returns 200)
- ❌ New issue: Provider context canceled immediately after startup
- 🔍 Hypothesis: One of the core services (cluster/bidengine/manifest) might be terminating when there are no active leases
- 🔍 Next: Need to identify which service is calling Done() immediately and why

**Files Modified:**
1. `/etc/nixos/kubernetes-manifests/akash-provider/PROVIDER_VALUES_v0.11.0.yaml`
2. `ConfigMap/akash-provider-script` - Updated run.sh with `--hostname-operator-endpoint` flag

**Helm Revision:** 53 (2 revisions with static endpoint workaround)

**Root Cause Analysis:**
- **PRIMARY BUG:** DNS trailing dot in `cluster/util/service_discovery_agent.go:167-169`
  - Provider uses `choice.Target` directly without stripping trailing dot
  - Creates malformed HTTP URL with dot before port number
  - **Fix:** Add `target := strings.TrimSuffix(choice.Target, ".")` before URL construction

- **SECONDARY BUG:** Provider context canceled immediately after startup
  - All services ready but main provider context is canceled within milliseconds of gRPC start
  - Balance checker receives "context canceled" before first blockchain sync check
  - **Hypothesis:** One of core services (cluster/bidengine/manifest) terminates when provider has no active leases
  - **Requires:** Investigation of service lifecycle and whether provider needs active deployments to run

## Previous Updates (2026-03-25 03:49 UTC)

### ✅ Cloudflare Tunnel Configuration (Fixed)
**Issue:** Tunnel routing to wrong NodePorts (30843/30844 instead of dynamically assigned 32294/31420)
**Files Modified:**
- `/etc/nixos/modules/services/akash-cloudflare-integration.nix` - Updated default endpoints
- `/etc/nixos/hosts/zephyr/configuration.nix` - Updated ingress rules and endpoint references
- `/etc/nixos/modules/services/akash-provider.nix` - Updated hardcoded NodePorts
- `/etc/nixos/kubernetes-manifests/akash-provider/PROVIDER_VALUES_v0.11.0.yaml` - Changed to NodePort type
**Solution:** Updated all configurations to use correct NodePorts (32294/31420)
**Status:** ✅ Resolved - NixOS rebuilt, cloudflared restarted with correct config

### ✅ Provider Service NodePort (Fixed)
**Issue:** Provider service was ClusterIP, inaccessible from Cloudflare tunnel
**Solution:** Changed service type to NodePort, Kubernetes assigned ports 32294 (API) and 31420 (gRPC)
**Status:** ✅ Resolved - Service accessible on nexus NodePorts

### ✅ ConfigMap Hostname Fix (Fixed)
**Issue:** ConfigMap had wrong hostname `provider.provider.reverb256.ca` instead of `provider.reverb256.ca`
**Root Cause:** Helm chart template hardcoding incorrect hostname
**Solution:** Manually patched ConfigMap with kubectl patch
**Status:** ✅ Resolved - ConfigMap now has correct hostname

### ✅ Hostname Operator API Connectivity (Fixed)
**Issue:** Hostname operator couldn't reach Kubernetes API server at 10.0.0.1:443
**Root Cause:** Stale hostname operator pod with cached DNS/connection state
**Solution:** Restarted hostname operator pod
**Status:** ✅ Resolved - hostname operator now connecting successfully

## Previous Fixes (2026-03-25 03:40 UTC)

### ✅ Hostname Operator API Connectivity (Fixed)
**Issue:** Hostname operator couldn't reach Kubernetes API server at 10.0.0.1:443
**Root Cause:** Stale hostname operator pod with cached DNS/connection state
**Solution:** Restarted hostname operator pod
**Status:** ✅ Resolved - hostname operator now connecting successfully

### ✅ ConfigMap Hostname Fix (Fixed)
**Issue:** ConfigMap had wrong hostname `provider.provider.reverb256.ca` instead of `provider.reverb256.ca`
**Root Cause:** Helm chart template hardcoding incorrect hostname
**Solution:** Manually patched ConfigMap with kubectl patch
**Status:** ✅ Resolved - ConfigMap now has correct hostname

### ❌ Provider Still Crashing (ONGOING)
**Error:** "cluster service terminated with error" err="context canceled"
**Status:** Provider starts successfully but cluster service crashes immediately
**Next Steps:**
- Investigate provider attributes on-chain (empty attributes array)
- Check if provider needs GPU/capability configuration on blockchain
- Review provider cluster service logs for more specific error details

## Remaining Investigation

### Primary Focus: Provider Attributes Configuration
**Theory:** Provider has empty `attributes: []` on-chain, no GPU capabilities advertised
**Evidence:** Earlier investigation showed provider attributes array is empty
**Action:** Query blockchain for provider attributes and configure if missing
**Commands:**
```bash
# From provider pod
provider-services query provider get --owner akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

## Hypotheses (DEPRECATED - See above fixes)

### ❌ Hypothesis 1: Version Mismatch (DISPROVED)
**Theory:** Commit message suggests v0.10.7 was working, not v0.11.0
**Evidence:** Commit message explicitly mentions downgrade to v0.10.7
**Test:** ❌ Tested - version changes don't fix this issue (see CRITICAL FINDING below)

### ❌ Hypothesis 2: Hostname Configuration (FIXED)
**Theory:** Wrong hostname structure causing health check failures
**Evidence:** ConfigMap had `provider.provider.reverb256.ca`
**Solution:** ✅ Fixed - patched ConfigMap to `provider.reverb256.ca`

### ❌ Hypothesis 3: Bidengine Configuration (DISPROVED)
**Theory:** Bidengine requires additional configuration not in default values
**Evidence:** Bidengine crashes before processing any orders
**Finding:** Bidengine crash is symptom of deeper cluster service issue, not bidengine-specific config

### ❌ Hypothesis 4: Inventory Not Ready (DISPROVED)
**Theory:** Bidengine starts before inventory operator completes hardware discovery
**Evidence:** "starting with existing reservations: qty=0"
**Finding:** Inventory operator is running and accessible, not the root cause

---

## CRITICAL FINDING: Version Changes Do NOT Fix This Issue

### ❌ FAILED: Version Changes
**Tested Versions:**
- v0.11.0 (chart 15.0.0) - Same error
- v0.10.7 (chart 14.0.8) - Same error
- Multiple revisions with different configs - Same error

**Conclusion:** The "client is not running" error persists across ALL provider versions.
**Root Cause:** NOT a version-specific bug. This is a **configuration or setup issue**.

### 🚫 PERMANENT NOTE: Do NOT Try Version Changes
**DO NOT** upgrade or downgrade the provider version to fix this error.
It will NOT help. Focus on configuration and setup instead.
```bash
helm upgrade akash-provider akash/provider \
  --namespace akash-services \
  --version 14.0.8 \
  --values kubernetes-manifests/akash-provider/PROVIDER_VALUES_WORKING.yaml \
  --reset-values
```

### 2. Query Provider Attributes from Blockchain
```bash
# From a pod with provider-services CLI
kubectl run -it --rm debug --image=ghcr.io/akash-network/provider:0.10.7 --restart=Never
provider-services query provider get --owner akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

### 3. Add Inventory Wait to Init Script
Modify init.sh to wait for inventory operator:
```bash
# Wait for inventory operator to be accessible
echo "Waiting for inventory operator..."
for i in $(seq 1 30); do
  if nc -z operator-inventory.akash-services.svc.cluster.local 8081; then
    echo "✓ Inventory operator ready"
    break
  fi
  sleep 2
done
```

### 4. Check Bidengine-Specific Configuration
Review Helm chart values for bidengine configuration options:
```bash
helm show values akash/provider --version 15.0.0 | grep -A 10 -i bid
```

---

## Files Modified

1. **PROVIDER_VALUES_v0.11.0.yaml** - Current working configuration
   - Memory limits: 2Gi
   - Withdrawal period: Empty
   - Inventory: beta2, beta3, ram
   - Environment: AKASH_FROM, AP_CERT_ISSUER_EMAIL

2. **PROVIDER_VALUES_WORKING.yaml** - v0.10.7 configuration
   - Based on commit 740804b (before issues)
   - Chart 14.0.8, App v0.10.7

3. **PROVIDER_VALUES.yaml** - Context7-aligned configuration
   - Comprehensive configuration with all fixes documented
   - Complete inventory and hostname operator setup

---

## References

- **Akash Provider Docs:** https://github.com/akash-network/provider
- **Context7 Skill:** /akash (comprehensive Akash Network documentation)
- **Working Commit:** b7c239c (comprehensive fixes)
- **Git History:** Commit messages suggest v0.10.7 was stable

---

## Notes

- ✅ All initialization steps succeed (key import, RPC check, cert validation)
- ✅ Provider service starts successfully
- ✅ Inventory operator connection established
- ✅ gRPC server starts on port 8444
- ❌ Bidengine crashes immediately after startup
- ⚠️ "context canceled" suggests service client initialization failure

**Recommendation:** Test v0.10.7 first (Hypothesis 1), as commit message explicitly mentions this version was working.
