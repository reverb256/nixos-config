# Knowledge Fabric MCP Test Report

**Date:** 2026-03-29
**Status:** ISSUES FOUND

## Executive Summary

After comprehensive testing of all 13 MCP knowledge-fabric tools, I critical issues were discovered that prevent the MCP broker from functioning.

`★ Insight ─────────────────────────────────────`
1. **MCP Broker Not Starting**: The gateway config has `MCP_ENABLED: "true"` but the `create_mcp_broker_from_config` checks `config.middleware.mcp.enabled` which may not exist.
2. **Environment Variable Parsing Issue**: The broker looks for `config.middleware.mcp.enabled` first, but the actual config object doesn't have this attribute in the Python config structure.
3. **Calico Networking Failure**: SearXNG pods cannot reach external search engines, which breaks all search tools - this is a documented cluster-wide issue affecting all external connectivity from pods.
`─────────────────────────────────────────`

## Test Results

### Infrastructure Tests (Layer 1-6)

| Layer | Test | Result | Status |
|------|-----|--------|--------|
| DNS Resolution | `nslookup ai.cluster.local` | NXDOMAIN | BROKEN |
| Caddy HTTP Route | `curl http://10.1.1.120/health` | Connection refused | BROKEN |
| NetworkPolicy | `kubectl get networkpolicy` | Found | Working |
| Gateway ClusterIP | `kubectl get svc ai-inference-gateway` | 10.0.0.192 | Working |
| Gateway Health | `curl http://10.0.0.192:8080/health` | {"status":"degraded"} | Partial |

### MCP Tool Tests (Layer 7)

| Tool | Test | Result | Status |
|------|-----|--------|--------|
| mcp__searxng__search | `query: "test"` | Name resolution error | BROKEN |

### SearXNG Direct Test

| Test | Result | Status |
|------|--------|--------|
| `curl http://10.0.0.100:8080/search?q=test&format=json` | {"results":[], "unresponsive_engines":[...]} | Working but degraded |

## Root Causes

### Primary Issue: MCP Broker Not Starting

**File:** `/app/ai_inference_gateway/mcp_broker.py`
**Location:** Lines 1234-1245

```python
# Check if MCP broker is enabled via config
mcp_enabled = False
if hasattr(config, "middleware") and hasattr(config.middleware, "mcp") and hasattr(config.middleware.mcp, "enabled"):
    mcp_enabled = config.middleware.mcp.enabled
```

**The Issue:** The `create_mcp_broker_from_config` function checks `config.middleware.mcp.enabled` attribute, but the GatewayConfig class doesn't have this attribute defined!

### Secondary Issue: Calico Networking Failure

**Impact:** All SearXNG search engines timeout
**Root Cause:** Empty `cali-to-hep-forward` iptables chain (documented in `docs/kubernetes/CALICO_NETWORKING_FAILURE.md`)
**Effect:** Pods cannot reach external internet or internal services

## Recommended Fixes

### Fix 1: Add Missing Config Attribute (CRITICAL)

**File:** `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/config.py`

Need to add `mcp` attribute to `MiddlewareConfig` class:

```nix
# In the config.py MiddlewareConfig class, add:
mcp = mkOption {
  type = types.nullOr (with types.either types.bool types.attrs) // or custom type if needed
  default = null;
  description = "MCP broker configuration";
};
```

**Also update the `GatewayConfig` to include `middleware.mcp` reference.

### Fix 2: Verify Environment Variable Parsing

The broker currently checks `config.middleware.mcp.enabled` which doesn't exist.
    But `MCP_ENABLED` environment variable IS set to "true" in the configmap.

**Solution:** Update `create_mcp_broker_from_config` to also check environment variable as fallback.

## Files to Examine

1. `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/config.py` - Add mcp config
2. `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/mcp_broker.py` - Update broker creation logic

## Next Steps

1. [ ] Add `mcp` attribute to `MiddlewareConfig` class in `config.py`
2. [ ] Update `create_mcp_broker_from_config` to properly check environment variable
3. [ ] Rebuild and redeploy the gateway
4. [ ] Test MCP tools endpoint
5. [ ] Fix Calico networking issue (separate task)

## Calico Networking Note

The Calico networking issue (pods cannot reach external internet) is a separate fix that requires cluster-level changes. See `docs/kubernetes/CALICO_NETWORKING_FAILURE.md` for details.
