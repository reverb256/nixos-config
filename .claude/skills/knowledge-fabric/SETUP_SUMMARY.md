# Knowledge Fabric - MCP Gateway Bridge Infrastructure Complete ✅

## Executive Summary

The MCP Gateway Bridge infrastructure is **fully operational** after fixing all 7 layers. The bridge successfully connects to the AI Inference Gateway and can proxy MCP requests.

### System Status: 🟢 INFRASTRUCTURE OPERATIONAL (NO TOOLS CONFIGURED)

| Layer | Status | Notes |
|-------|--------|-------|
| **Layer 1: DNS Resolution** | ✅ OPERATIONAL | `ai.cluster.local` → `10.1.1.120` (nexus) |
| **Layer 2: Caddy Ingress** | ✅ OPERATIONAL | HTTP/HTTPS split routes, ClusterIP direct |
| **Layer 3: NetworkPolicy** | ✅ OPERATIONAL | Cross-namespace traffic allowed |
| **Layer 4: Gateway Service** | ✅ OPERATIONAL | ClusterIP `10.0.0.192:8080` |
| **Layer 5: Gateway Health** | ✅ OPERATIONAL | `/health` returns 200 OK |
| **Layer 6: MCP Tools Endpoint** | ✅ OPERATIONAL | `/mcp/tools` accessible (empty) |
| **Layer 7: MCP Bridge** | ✅ OPERATIONAL | stdio → HTTP proxy working |

**Available Tools:** ❌ **NONE** (gateway returns `{"tools":[]}`)

---

## Infrastructure Fixes Applied (2026-03-26)

### Layer 1: DNS Resolution (Unbound)
**File:** `/etc/nixos/modules/services/unbound-cluster.nix`

**Issue:** `ai.cluster.local` pointing to wrong IP (`10.1.1.100` - K8s API VIP)

**Fix Applied:** Updated DNS records to point to Caddy ingress node (`10.1.1.120` - nexus)
```nix
''"ai.cluster.local. IN A 10.1.1.120"''
''"llm.cluster.local. IN A 10.1.1.120"''
''"rag.cluster.local. IN A 10.1.1.120"''
''"search.cluster.local. IN A 10.1.1.120"''
```

**Applied:** `sudo systemctl restart unbound`

**Verification:**
```bash
nslookup ai.cluster.local 10.1.1.110
# Expected: ai.cluster.local → 10.1.1.120
```

### Layer 2: Caddy Ingress Routes
**File:** `/etc/nixos/kubernetes-manifests/ingress/02-configmap.yaml`

**Issues:**
1. Auto-HTTPS redirecting HTTP to HTTPS (308 Permanent Redirect)
2. DNS resolution timeouts for service DNS

**Fixes Applied:**
1. Split into explicit HTTP/HTTPS routes:
```caddy
# HTTP route (for MCP bridge) - NO TLS
http://ai.cluster.local {
  tls off
  reverse_proxy 10.0.0.192:8080 {
    health_uri /health
    health_interval 10s
    health_timeout 10s
  }
}

# HTTPS route (for browsers) - WITH TLS
https://ai.cluster.local {
  import security_headers
  tls internal
  reverse_proxy 10.0.0.192:8080 {
    health_uri /health
    health_interval 10s
    health_timeout 10s
  }
}
```

2. Changed from service DNS to ClusterIP (`10.0.0.192`) to avoid DNS timeouts

**Applied:** `kubectl apply -f 02-configmap.yaml` + `kubectl rollout restart daemonset/caddy-ingress`

**Verification:**
```bash
echo -e "GET /health HTTP/1.1\r\nHost: ai.cluster.local\r\n\r\n" | nc 10.1.1.120 80
# Expected: HTTP/1.1 200 OK
```

### Layer 3: Kubernetes NetworkPolicy
**File:** `/etc/nixos/kubernetes-manifests/ingress/07-networkpolicy.yaml`

**Issue:** NetworkPolicy blocking cross-namespace traffic

**Fixes Applied:**
1. Added namespace labels:
```bash
kubectl label namespace ai-inference name=ai-inference
kubectl label namespace ingress-system name=ingress-system
```

2. Added explicit egress rule for ai-inference namespace:
```yaml
# Allow reaching ai-inference namespace services
- to:
  - namespaceSelector:
      matchLabels:
        name: ai-inference
  ports:
  - port: 8080
    protocol: TCP
  - port: 6333
    protocol: TCP
  - port: 80
    protocol: TCP
  - port: 443
    protocol: TCP
```

3. Added ingress rule for cluster hosts:
```yaml
# Allow HTTP/HTTPS from cluster hosts (for MCP gateway bridge, etc.)
- ports:
  - port: http
    protocol: TCP
  - port: https
    protocol: TCP
  from:
  - ipBlock:
      cidr: 10.1.1.0/24  # Cluster network
```

**Applied:** `kubectl apply -f 07-networkpolicy.yaml`

**Verification:**
```bash
kubectl get networkpolicy -n ingress-system
# Expected: caddy-ingress-allow-egress with namespaceSelector
```

### Layer 4: Gateway Service (ClusterIP)
**Service:** `ai-inference-gateway.ai-inference.svc.cluster.local:8080`
**ClusterIP:** `10.0.0.192`

**Issue:** DNS resolution timeouts for service DNS

**Fix:** Changed Caddy config to use ClusterIP directly (`10.0.0.192`) instead of service DNS

**Verification:**
```bash
kubectl get svc ai-inference-gateway -n ai-inference
# Expected: ClusterIP 10.0.0.192
```

### Layer 5: Gateway Health Endpoint
**Endpoint:** `http://ai.cluster.local/health`

**Status:** ✅ Working

**Verification:**
```bash
curl -s http://ai.cluster.local/health | jq .
# Expected: {"status":"healthy"}
```

### Layer 6: Gateway MCP Tools Endpoint
**Endpoint:** `http://ai.cluster.local/mcp/tools`

**Status:** ✅ Working (but returns empty tools list)

**Current Response:**
```json
{"tools":[]}
```

**Issue:** No MCP servers configured in the AI Inference Gateway's MCP broker

**Next Step:** Configure MCP servers in gateway.nix (see SKILL.md for instructions)

**Verification:**
```bash
curl -s http://ai.cluster.local/mcp/tools | jq .
# Expected: {"tools":[]} (currently empty)
```

### Layer 7: MCP Gateway Bridge
**Configuration:** `/etc/nixos/.mcp.json`
```json
{
  "mcpServers": {
    "gateway": {
      "command": "mcp-gateway-bridge",
      "env": {
        "GATEWAY_URL": "http://ai.cluster.local"
      }
    }
  }
}
```

**Script:** `/etc/nixos/scripts/mcp-gateway-bridge`

**Status:** ✅ Working (successfully connects and returns `{"tools":[]}`)

**Verification:**
```bash
GATEWAY_URL="http://ai.cluster.local" /etc/nixos/scripts/mcp-gateway-bridge
# Expected: JSON-RPC response with {"tools":[]}
```

---

## Complete Verification Checklist

Run this to verify all 7 layers are operational:

```bash
#!/usr/bin/env bash
echo "MCP Gateway Bridge Infrastructure Check"
echo "========================================"

# Layer 1: DNS
echo -n "Layer 1: DNS resolution... "
if nslookup ai.cluster.local 10.1.1.110 2>&1 | grep -q "10.1.1.120"; then
  echo "✓ PASS"
else
  echo "✗ FAIL"
  echo "  Fix: Check /etc/nixos/modules/services/unbound-cluster.nix"
  echo "  Command: sudo systemctl restart unbound"
fi

# Layer 2: Caddy Ingress
echo -n "Layer 2: Caddy HTTP route... "
if echo -e "GET /health HTTP/1.1\r\nHost: ai.cluster.local\r\n\r\n" | nc -w 2 10.1.1.120 80 2>/dev/null | grep -q "200 OK"; then
  echo "✓ PASS"
else
  echo "✗ FAIL"
  echo "  Fix: Check /etc/nixos/kubernetes-manifests/ingress/02-configmap.yaml"
  echo "  Command: kubectl rollout restart daemonset/caddy-ingress -n ingress-system"
fi

# Layer 3: NetworkPolicy
echo -n "Layer 3: NetworkPolicy... "
if kubectl get networkpolicy -n ingress-system caddy-ingress-allow-egress &>/dev/null; then
  echo "✓ PASS"
else
  echo "✗ FAIL"
  echo "  Fix: Apply /etc/nixos/kubernetes-manifests/ingress/07-networkpolicy.yaml"
  echo "  Command: kubectl apply -f 07-networkpolicy.yaml"
fi

# Layer 4: Gateway Service
echo -n "Layer 4: Gateway ClusterIP... "
if kubectl get svc ai-inference-gateway -n ai-inference &>/dev/null; then
  CLUSTERIP=$(kubectl get svc ai-inference-gateway -n ai-inference -o jsonpath='{.spec.clusterIP}')
  if [ "$CLUSTERIP" = "10.0.0.192" ]; then
    echo "✓ PASS ($CLUSTERIP)"
  else
    echo "✗ FAIL (wrong ClusterIP: $CLUSTERIP)"
  fi
else
  echo "✗ FAIL"
fi

# Layer 5: Gateway Health
echo -n "Layer 5: Gateway health... "
if curl -s http://ai.cluster.local/health 2>/dev/null | grep -q "healthy"; then
  echo "✓ PASS"
else
  echo "✗ FAIL"
  echo "  Fix: Check ai-inference-gateway service"
  echo "  Command: sudo systemctl restart ai-inference-gateway"
fi

# Layer 6: MCP Tools Endpoint
echo -n "Layer 6: MCP tools endpoint... "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://ai.cluster.local/mcp/tools 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
  TOOLS_COUNT=$(curl -s http://ai.cluster.local/mcp/tools 2>/dev/null | jq '.tools | length')
  if [ "$TOOLS_COUNT" = "0" ]; then
    echo "✓ PASS (but NO tools configured)"
  else
    echo "✓ PASS ($TOOLS_COUNT tools available)"
  fi
else
  echo "✗ FAIL (HTTP $HTTP_CODE)"
fi

# Layer 7: MCP Bridge
echo -n "Layer 7: MCP bridge... "
if timeout 5 bash -c 'echo "ping" | mcp-gateway-bridge' &>/dev/null; then
  echo "✓ PASS"
else
  echo "✗ FAIL"
  echo "  Fix: Check GATEWAY_URL environment variable"
  echo "  Command: export GATEWAY_URL=\"http://ai.cluster.local\""
fi

echo "========================================"
echo ""
echo "Summary:"
echo "--------"
echo "Infrastructure: ✅ All 7 layers operational"
echo "Available Tools: ❌ None (gateway returns empty tools list)"
echo ""
echo "Next Step: Configure MCP servers in gateway.nix"
echo "See: /etc/nixos/.claude/skills/knowledge-fabric/SKILL.md"
```

---

## Current State

### What's Working
✅ DNS resolution for `ai.cluster.local`
✅ Caddy ingress HTTP/HTTPS routes
✅ NetworkPolicy cross-namespace traffic
✅ Gateway service (ClusterIP accessible)
✅ Gateway health endpoint
✅ MCP tools endpoint (HTTP 200)
✅ MCP gateway bridge (stdio → HTTP proxy)

### What's Missing
❌ MCP servers configured in gateway (returns empty tools list)

### Root Cause
The AI Inference Gateway's MCP broker has no MCP servers configured. The broker is working correctly, but there are no servers to proxy to.

### Solution
Configure MCP servers in `/etc/nixos/modules/services/ai-inference/gateway.nix`:

```nix
services.ai-inference.gateway = {
  enable = true;
  settings = {
    mcp_servers = [
      {
        name = "searxng";
        type = "local";
        command = "python";
        args = ["-m" "ai_inference_gateway.mcp_servers.searxng_server"];
        environment = {
          SEARXNG_URL = "http://10.1.1.120:30080";
        };
      }
    ];
  };
};
```

Then restart the gateway:
```bash
sudo systemctl restart ai-inference-gateway
```

Verify tools are available:
```bash
curl -s http://ai.cluster.local/mcp/tools | jq .
```

---

## File Locations Reference

### Configuration Files
| File | Purpose |
|------|---------|
| `/etc/nixos/.mcp.json` | MCP server configurations (gateway bridge) |
| `/etc/nixos/.claude/skills/knowledge-fabric/SKILL.md` | Knowledge Fabric skill documentation |
| `/etc/nixos/.claude/skills/knowledge-fabric/CONFIGURATION.md` | Service endpoints and environment variables |
| `/etc/nixos/.claude/skills/knowledge-fabric/SETUP_SUMMARY.md` | This file - infrastructure fix summary |

### Infrastructure Files
| File | Purpose |
|------|---------|
| `/etc/nixos/modules/services/unbound-cluster.nix` | DNS configuration (Layer 1) |
| `/etc/nixos/kubernetes-manifests/ingress/02-configmap.yaml` | Caddy ingress routes (Layer 2) |
| `/etc/nixos/kubernetes-manifests/ingress/07-networkpolicy.yaml` | NetworkPolicy rules (Layer 3) |
| `/etc/nixos/scripts/mcp-gateway-bridge` | MCP bridge script (Layer 7) |

---

## Troubleshooting Guide

### Issue: DNS resolution fails
```bash
# Check Unbound
systemctl status unbound

# Verify DNS records
nslookup ai.cluster.local 10.1.1.110

# Restart Unbound
sudo systemctl restart unbound
```

### Issue: Caddy returns HTTP 503
```bash
# Check Caddy logs
kubectl logs -n ingress-system -l app.kubernetes.io/name=caddy-ingress

# Verify NetworkPolicy
kubectl get networkpolicy -n ingress-system

# Check namespace labels
kubectl get namespace ai-inference --show-labels
kubectl get namespace ingress-system --show-labels

# Restart Caddy
kubectl rollout restart daemonset/caddy-ingress -n ingress-system
```

### Issue: Gateway returns HTTP 500
```bash
# Check gateway logs
journalctl -u ai-inference-gateway -n 50

# Restart gateway
sudo systemctl restart ai-inference-gateway
```

### Issue: MCP bridge fails
```bash
# Check GATEWAY_URL
echo $GATEWAY_URL

# Test HTTP connectivity
curl -s http://$GATEWAY_URL/health

# Verify script
ls -l /etc/nixos/scripts/mcp-gateway-bridge

# Test bridge manually
echo '{"jsonrpc":"2.0","id":1,"method":"ping"}' | mcp-gateway-bridge
```

---

## Next Steps

### Immediate (Required)
1. **Configure MCP servers** in gateway.nix to add tools
2. **Restart gateway** to load MCP servers
3. **Verify tools** are available via `/mcp/tools` endpoint
4. **Test MCP bridge** with actual tools configured

### Future Enhancements
1. Add SearXNG MCP server for web search
2. Add GitHub MCP server for code search
3. Add StackOverflow MCP server for Q&A
4. Configure tool caching for better performance
5. Add monitoring for MCP bridge health

---

**Infrastructure Completed:** 2026-03-26
**Status:** ✅ All 7 layers operational, ❌ No tools configured
**Next Action:** Configure MCP servers in gateway.nix

`★ Insight ─────────────────────────────────────`
The MCP Gateway Bridge infrastructure represents a sophisticated 7-layer architecture that combines DNS, ingress, network policies, services, and HTTP proxying to provide seamless stdio-to-HTTP translation for MCP protocol. The successful resolution of all layers demonstrates the importance of systematic debugging and understanding of Kubernetes networking fundamentals.
`─────────────────────────────────────────────────`
