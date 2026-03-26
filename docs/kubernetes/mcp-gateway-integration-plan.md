# MCP Gateway Integration Plan

**Created:** 2026-03-25
**Status:** READY TO IMPLEMENT
**Objective:** Fix Knowledge Fabric skill and MCP integration with SearXNG

---

## Current Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    ZEPHYR (10.1.1.110)                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  mcp-gateway-bridge (local Python script)               │  │
│  │  Config: GATEWAY_URL=http://10.0.0.192:8080            │  │
│  │  ❌ WRONG: ClusterIP not accessible from host!          │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              ↓                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  mcp-gateway-proxy DaemonSet (socat)                    │  │
│  │  localhost:8080 → localhost:30880 (NodePort)            │  │
│  │  ✅ Running on all 3 nodes                              │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                           │
│                                                                  │
│  VIP: 10.1.1.100 (Keepalived - floats between masters)          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────┐      │
│  │  AI Inference Gateway Service                         │      │
│  │  Type: NodePort                                      │      │
│  │  ClusterIP: 10.0.0.192 (NOT accessible from host)    │      │
│  │  NodePort: 30880 (accessible on all nodes)           │      │
│  │  Selector: app=ai-inference-gateway                   │      │
│  └──────────────────────────────────────────────────────┘      │
│                              ↓                                  │
│  ┌──────────────────────────────────────────────────────┐      │
│  │  Gateway Pod (10.244.98.6:8080)                      │      │
│  │  Status: Running, /health returns 200 OK            │      │
│  │  Location: ai-inference namespace                     │      │
│  └──────────────────────────────────────────────────────┘      │
│                                                                  │
│  IPVS Configuration (verified working):                          │
│  TCP  10.1.1.100:30880 rr → 10.244.98.6:8080                   │
│  TCP  10.1.1.110:30880 rr → 10.244.98.6:8080                   │
│  TCP  10.1.1.120:30880 rr → 10.244.98.6:8080                   │
│  TCP  10.1.1.130:30880 rr → 10.244.98.6:8080                   │
│  TCP  10.1.1.140:30880 rr → 10.244.98.6:8080                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Problem Statement

**PRIMARY ISSUE:** `.mcp.json` configured with wrong GATEWAY_URL
- Current: `http://10.0.0.192:8080` (ClusterIP)
- Problem: ClusterIP only accessible from within cluster
- Result: mcp-gateway-bridge cannot connect

**SECONDARY ISSUE:** Unnecessary complexity
- Socat DaemonSet adds hop (localhost:8080 → localhost:30880)
- VIP (10.1.1.100:30880) provides direct HA access
- Socat only useful if connecting to localhost:8080 specifically

---

## Solution Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  mcp-gateway-bridge (local Python script)                       │
│  Config: GATEWAY_URL=http://ai-inference-gateway.ai-inference.svc.cluster.local:8080
│  ✅ CORRECT: DNS name, HA, service discovery, maintainable     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    CoreDNS Service Discovery
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    ClusterIP Service                            │
│  ai-inference-gateway.ai-inference.svc.cluster.local:8080      │
│  Routes to healthiest gateway pod replica                       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  AI Inference Gateway Pod                                       │
│  /health endpoint: 200 OK                                       │
│  Knowledge Fabric API endpoints: /v1/search/*, /v1/web/*       │
└─────────────────────────────────────────────────────────────────┘
```

**Alternative: External Access (if ClusterIP not accessible)**
```
GATEWAY_URL: http://ai.cluster.local  # Caddy Ingress with TLS
```

---

## Implementation Plan

### Phase 1: Update Configuration (5 minutes)

**Task 1.1: Update .mcp.json**
- Change `GATEWAY_URL` from `http://10.0.0.192:8080` to `http://10.1.1.100:30880`
- Rationale: VIP provides HA access, NodePort accessible from any host
- File: `/etc/nixos/.mcp.json`
- Change: Line 40

**Task 1.2: Verify Socat DaemonSet Status**
- Check all 3 pods running (zephyr, nexus, forge/sentry)
- Decide: Keep for localhost:8080 compatibility OR remove if not needed
- Current: 3/3 pods running

### Phase 2: Test Connectivity (10 minutes)

**Task 2.1: Test VIP + NodePort from Zephyr**
```bash
curl http://10.1.1.100:30880/health
# Expected: 200 OK
```

**Task 2.2: Test from Other Nodes**
```bash
ssh nexus "curl http://10.1.1.100:30880/health"
ssh forge "curl http://10.1.1.100:30880/health"
# Expected: All return 200 OK
```

**Task 2.3: Test MCP Gateway Bridge**
```bash
GATEWAY_URL=http://10.1.1.100:30880 timeout 15 mcp-gateway-bridge ping_searxng
# Expected: Successful ping to SearXNG
```

### Phase 3: Test Knowledge Fabric Skill (15 minutes)

**Task 3.1: Test SearXNG MCP Tool**
```bash
# Use knowledge-fabric skill
# Query: "test search"
# Tool: mcp__gateway__search_research or mcp__gateway__web_search
# Expected: Search results from SearXNG
```

**Task 3.2: Test Multiple MCP Tools**
- search_code: GitHub, StackOverflow
- search_research: Google Scholar, arXiv
- web_search: General web search
- All should return results

**Task 3.3: Verify SearXNG Direct Access**
- Current: SEARXNG_URL=https://search.reverb256.ca (Caddy ingress)
- Test: Direct search through Knowledge Fabric
- Expected: Working searches without 500 errors

### Phase 4: Cleanup (5 minutes)

**Task 4.1: Decide on Socat DaemonSet**
- IF VIP works perfectly: Remove DaemonSet
- IF localhost:8080 needed elsewhere: Keep DaemonSet
- Document decision in STATUS.md

**Task 4.2: Update Documentation**
- Document GATEWAY_URL change in DECISION_LOG.md
- Update AGENTS.md with correct MCP configuration
- Add troubleshooting section for MCP connectivity

---

## Success Criteria

✅ **Phase 1 Complete:**
- .mcp.json updated with VIP + NodePort
- Socat DaemonSet status documented

✅ **Phase 2 Complete:**
- VIP + NodePort accessible from all nodes
- MCP gateway bridge connects successfully

✅ **Phase 3 Complete:**
- All Knowledge Fabric MCP tools return results
- SearXNG searches work without 500 errors
- End-to-end MCP integration functional

✅ **Phase 4 Complete:**
- Unnecessary components removed OR documented
- Documentation updated
- Decision log updated

---

## Rollback Plan

**IF Phase 2 Fails (VIP not accessible):**
- Revert .mcp.json to `http://127.0.0.1:8080` (use socat proxy)
- Remove Socat DaemonSet tolerations to ensure it runs everywhere
- Test localhost:8080 connectivity

**IF Phase 3 Fails (MCP tools broken):**
- Verify SearXNG URL in .mcp.json (https://search.reverb256.ca)
- Check Caddy ingress logs for errors
- Test SearXNG directly via curl
- Verify bot_detection.disabled in SearXNG config

---

## Testing Checklist

- [ ] .mcp.json GATEWAY_URL updated to `http://10.1.1.100:30880`
- [ ] VIP + NodePort accessible from zephyr: `curl http://10.1.1.100:30880/health`
- [ ] VIP + NodePort accessible from nexus: `ssh nexus "curl http://10.1.1.100:30880/health"`
- [ ] MCP gateway bridge connects: `timeout 15 mcp-gateway-bridge ping_searxng`
- [ ] Knowledge Fabric search_code works
- [ ] Knowledge Fabric web_search works
- [ ] Knowledge Fabric search_research works
- [ ] SearXNG direct access works (no 500 errors)
- [ ] Socat DaemonSet decision made (keep/remove)
- [ ] Documentation updated

---

## Time Estimate

- Phase 1: 5 minutes
- Phase 2: 10 minutes
- Phase 3: 15 minutes
- Phase 4: 5 minutes

**Total: 35 minutes**

---

## Next Steps

**READY TO IMPLEMENT:** Review and approve plan, then proceed with Phase 1.

**Questions for User:**
1. Should we remove the socat DaemonSet if VIP works?
2. Any specific Knowledge Fabric queries to test?
3. Are there other MCP servers that need testing?

