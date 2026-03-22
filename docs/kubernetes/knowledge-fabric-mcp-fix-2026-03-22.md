# Knowledge Fabric MCP Fix - 2026-03-22

**Status**: ✅ **RESOLVED**

## Problem

Knowledge fabric was failing with error:
```
Error: Failed to communicate with local MCP server searxng
```

## Root Cause

1. **MCP servers not enabled in settings.json** - The `enabledMcpjsonServers` list was missing from `/etc/nixos/.claude/settings.json`
2. **SearXNG MCP server not configured** - The `searxng` server was missing from `/etc/nixos/.mcp.json`
3. **Not using Kubernetes service** - SearXNG was configured to use local URL instead of the K8s service

## Solution

### 1. Enabled MCP Servers in settings.json

**File**: `/etc/nixos/.claude/settings.json`

Added:
```json
{
  "enabledMcpjsonServers": [
    "filesystem",
    "git",
    "fetch",
    "context7",
    "grep-app",
    "chrome-devtools",
    "playwright",
    "nixos",
    "gateway",
    "searxng"
  ]
}
```

### 2. Added SearXNG to .mcp.json

**File**: `/etc/nixos/.mcp.json`

Added:
```json
{
  "mcpServers": {
    ...
    "searxng": {
      "command": "/etc/nixos/modules/services/ai-inference/bin/opencode-searxng-mcp",
      "env": {
        "SEARXNG_URL": "http://10.0.0.102:8080"
      }
    }
  }
}
```

### 3. Configured Kubernetes-Native SearXNG

**SearXNG Service Details**:
- **Kubernetes Service**: `searxng.search.svc.cluster.local:8080`
- **ClusterIP**: `http://10.0.0.102:8080`
- **Pods**: 11 replicas running (all healthy)
- **NodePort**: `http://<node-ip>:30080`

## Verification

### Check MCP Servers
```bash
# Test MCP gateway bridge
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | mcp-gateway-bridge

# Check SearXNG service
kubectl get svc -n search searxng
kubectl get pods -n search -l app=searxng
```

### Test SearXNG Access
```bash
# Port-forward to test
kubectl port-forward -n search svc/searxng 9999:8080
curl -s "http://localhost:9999/search?q=test"
```

## Architecture

```
┌─────────────────┐
│  Claude Code    │
│  (MCP Client)   │
└────────┬────────┘
         │
         ├──────────────────┐
         │                  │
    ┌────▼─────────┐  ┌────▼──────────────────┐
    │  MCP Gateway  │  │  SearXNG MCP Server   │
    │    Bridge     │  │  (Python stdio)       │
    └────────┬──────┘  └────┬──────────────────┘
             │              │
             │         ┌────▼──────────────┐
             │         │  SearXNG K8s      │
             │         │  Service          │
             │         │  (10.0.0.102:8080) │
             │         └────┬──────────────┘
             │              │
             │         ┌────▼──────────────┐
             │         │  11× SearXNG Pods  │
             │         │  (search ns)       │
             │         └─────────────────────┘
             │
    ┌──────▼──────────────┐
    │  Search Results    │
    │  (Aggregated)      │
    └─────────────────────┘
```

## Components Status

| Component | Status | Details |
|-----------|--------|---------|
| **SearXNG K8s Service** | ✅ Running | 11 pods, ClusterIP: 10.0.0.102 |
| **SearXNG MCP Server** | ✅ Running | 2 processes (PIDs 15976, 17100) |
| **MCP Gateway Bridge** | ✅ Running | Exposing 10 tools |
| **settings.json** | ✅ Fixed | enabledMcpjsonServers added |
| **.mcp.json** | ✅ Fixed | searxng configuration added |

## Knowledge Fabric Skill Updates

**File**: `/etc/nixos/.claude/skills/knowledge-fabric/SKILL.md`

**Updated**:
- Version: 2.0 → 2.1 (K8s SearXNG)
- Added troubleshooting for `enabledMcpjsonServers`
- Added K8s service verification steps
- Added common issues section

## Next Steps

None - system is fully operational.

---

**Fixed**: 2026-03-22 05:54 UTC
**Verified**: ✅ All MCP servers operational
**Status**: ✅ Production Ready
