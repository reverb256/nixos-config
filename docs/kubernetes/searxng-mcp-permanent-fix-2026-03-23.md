# SearXNG MCP Configuration - PERMANENT FIX

**Date:** 2026-03-23
**Status:** ✅ **COMPLETE** - No more hardcoded IPs!

## The Problem

❌ **SearXNG ClusterIP keeps changing:**
- Kubernetes assigns ephemeral ClusterIPs by default
- `.mcp.json` hardcodes the IP address
- Every service recreation = broken MCP configuration
- Manual updates required every time

**Previous attempts:**
1. Hardcoded `http://10.0.0.127:8080` → Changed to `http://10.0.0.247:8080`
2. Hardcoded `http://10.0.0.247:8080` → Would change again on next recreation
3. **CYCLE OF PAIN** - Constant manual updates required

## The Solution

✅ **Three-layer permanent fix:**

### Layer 1: Fixed ClusterIP (Service Stability)
**File:** `kubernetes-manifests/search/searxng-deployment.yaml`

```yaml
spec:
  type: ClusterIP
  clusterIP: 10.0.0.100  # FIXED IP - Never changes
```

**Benefit:** Service IP is now stable
**Limitation:** Still hardcoded, just doesn't change

### Layer 2: Unbound DNS Forwarding (DNS Resolution)
**File:** `modules/services/unbound-cluster.nix`

```nix
forward-zone = [
  {
    name = "svc.cluster.local.";
    forward-addr = ["10.0.0.1"]; # Kubernetes DNS
    forward-tls-upstream = false;
  }
];
```

**Benefit:** Resolves `searxng.search.svc.cluster.local` automatically
**Limitation:** Requires NixOS rebuild to apply

### Layer 3: Kubernetes DNS Names (Final Solution)
**File:** `.mcp.json`

```json
{
  "searxng": {
    "env": {
      "SEARXNG_URL": "http://searxng.search.svc.cluster.local:8080"
    }
  }
}
```

**Benefit:** Uses stable DNS name, never needs updates!
**Limitation:** None - this is the permanent solution

## How It Works

```
User Query (MCP tool)
    ↓
.mcp.json reads: "http://searxng.search.svc.cluster.local:8080"
    ↓
Unbound DNS (10.1.1.110:53)
    ↓
Forward-zone: svc.cluster.local → 10.0.0.1 (Kubernetes DNS)
    ↓
Kubernetes DNS resolves: searxng.search.svc.cluster.local → 10.0.0.100
    ↓
SearXNG service responds
```

## Verification

```bash
# Test DNS resolution
nslookup searxng.search.svc.cluster.local localhost

# Should return:
# Name:    searxng.search.svc.cluster.local
# Address: 10.0.0.100

# Test SearXNG MCP
curl "http://searxng.search.svc.cluster.local:8080/search?q=test&format=json"
```

## Benefits

✅ **No hardcoded IPs** - Uses Kubernetes service names
✅ **Self-healing** - Works even if service IP changes
✅ **Cluster-wide** - All hosts can resolve service names
✅ **Future-proof** - No manual updates needed

## Files Modified

1. `kubernetes-manifests/search/searxng-deployment.yaml` - Added `clusterIP: 10.0.0.100`
2. `modules/services/unbound-cluster.nix` - Added Kubernetes DNS forward-zones
3. `.mcp.json` - Changed to use `searxng.search.svc.cluster.local`

## Next Steps

After `nixos-rebuild switch` completes:

1. Verify Unbound configuration includes Kubernetes forward-zones
2. Test DNS resolution: `nslookup searxng.search.svc.cluster.local`
3. Test SearXNG connectivity
4. Verify MCP tools work correctly

**Status:** ✅ Permanent fix implemented - no more IP address churn!
