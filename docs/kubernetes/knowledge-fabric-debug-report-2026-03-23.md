# Knowledge Fabric & MCP - Comprehensive Debug Report

**Date:** 2026-03-23
**Status:** 🔄 **IN PROGRESS** - Fixes applied, rebuild in progress

## Issues Found & Fixed

### ❌ Issue 1: SearXNG ClusterIP Keeps Changing
**Problem:** Kubernetes assigns ephemeral ClusterIPs, breaking MCP config

**Root Cause:** No fixed ClusterIP in service definition

**Fix Applied:**
```yaml
# kubernetes-manifests/search/searxng-deployment.yaml
spec:
  clusterIP: 10.0.0.100  # FIXED IP
```

**Status:** ✅ Applied

---

### ❌ Issue 2: Wrong Kubernetes DNS IP
**Problem:** Unbound configured to forward to `10.0.0.1`, but actual K8s DNS is at `10.0.0.10`

**Root Cause:** Assumption about default Kubernetes DNS IP

**Fix Applied:**
```nix
# modules/services/unbound-cluster.nix
forward-zone = [
  {
    name = "svc.cluster.local.";
    forward-addr = ["10.0.0.10"]; # Corrected from 10.0.0.1
  }
];
```

**Status:** ✅ Applied

---

### ❌ Issue 3: cluster.local in local-zone
**Problem:** `cluster.local` marked as static zone, preventing forwarding to Kubernetes DNS

**Root Cause:** Misunderstanding of local-zone vs forward-zone interaction

**Fix Applied:**
```nix
# Removed cluster.local from local-zone
local-zone = [
  # "cluster.local" REMOVED - now forwarded
  "lan" static
  # ...
];
```

**Status:** ✅ Applied

---

### ❌ Issue 4: Hardcoded IPs in .mcp.json
**Problem:** Multiple hardcoded IPs that keep changing

**Root Cause:** Using ClusterIPs instead of DNS names

**Fix Applied:**
```json
{
  "searxng": {
    "env": {
      "SEARXNG_URL": "http://searxng.search.svc.cluster.local:8080"
    }
  }
}
```

**Status:** ✅ Applied

---

## Current Status

### ✅ Working Components
- **Kubernetes Service:** `10.0.0.100` (fixed IP)
- **SearXNG Pods:** 3/3 Running
- **Kubernetes DNS:** `10.0.0.10` (kube-dns)
- **Unbound Service:** Active
- **MCP Config:** Using DNS names

### 🔄 Pending (Rebuild in Progress)
- **Unbound Configuration:** Waiting for `nixos-rebuild switch` to apply new forward-zones
- **DNS Resolution:** Will work after rebuild

### ⏳ Not Yet Tested
- **DNS Resolution:** `searxng.search.svc.cluster.local`
- **SearXNG MCP Server:** End-to-end connectivity
- **Knowledge Fabric Tools:** MCP tool functionality

---

## Architecture (After Fix)

```
┌─────────────────────────────────────────────────────────────┐
│                     User/Agent Query                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  .mcp.json: "http://searxng.search.svc.cluster.local:8080" │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Unbound DNS (10.1.1.110:53)                                 │
│  Forward-zone: svc.cluster.local → 10.0.0.10                 │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Kubernetes DNS (kube-dns: 10.0.0.10)                       │
│  Resolves: searxng.search → 10.0.0.100                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  SearXNG Service (ClusterIP: 10.0.0.100)                   │
│  → Pods: searxng-5cdd885545-* (3x Running)                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Verification Steps (After Rebuild)

```bash
# 1. Verify Unbound has correct forward-zones
grep -A2 "svc.cluster.local" /etc/unbound/unbound.conf

# 2. Test DNS resolution
nslookup searxng.search.svc.cluster.local localhost

# 3. Test SearXNG connectivity
curl "http://searxng.search.svc.cluster.local:8080/search?q=test&format=json"

# 4. Test MCP server
/etc/nixos/modules/services/ai-inference/bin/opencode-searxng-mcp

# 5. Test knowledge fabric tools
# (From agent) Use search_code, web_search, etc.
```

---

## Key Learnings

1. **Kubernetes DNS is NOT always at 10.0.0.1**
   - Actual location: `kube-dns.kube-system.svc.cluster.local`
   - IP: `10.0.0.10` (in this cluster)

2. **Fixed ClusterIP + DNS Forwarding = Permanent Solution**
   - Layer 1: Fixed ClusterIP (service stability)
   - Layer 2: DNS forwarding (name resolution)
   - Layer 3: DNS names in config (no hardcoded IPs)

3. **local-zone Blocks Forwarding**
   - If domain in local-zone → won't use forward-zone
   - Must remove cluster.local from local-zone

4. **NixOS Module Changes Require Rebuild**
   - Just restarting service = old config
   - Must run `nixos-rebuild switch` to apply module changes

---

## Next Actions

1. ⏳ **Wait for rebuild** to complete
2. ⏳ **Restart Unbound** to load new config
3. ⏳ **Test DNS resolution** end-to-end
4. ⏳ **Test MCP server** functionality
5. ⏳ **Verify knowledge fabric tools** working

**Rebuild Status:** 🔄 In Progress
**Estimated Time:** 2-3 minutes
**Current Confidence:** 95% (all issues identified and fixed)
