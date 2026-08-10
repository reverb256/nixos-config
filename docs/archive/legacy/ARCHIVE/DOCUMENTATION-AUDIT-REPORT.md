# Documentation Audit Report — 2026-04-24

## Summary

Systematic verification of documentation claims against actual cluster state revealed **multiple discrepancies** that need correction.

---

## Critical Findings

### 1. Namespace Count
**Claimed:** 23 namespaces
**Actual:** 22 namespaces
**Status:** ❌ Incorrect

### 2. CNI Configuration
**Claimed:** Calico CNI (Flannel disabled)
**Actual:** Flannel VXLAN (UDP 8472)
**Status:** ✅ Fixed in previous correction

### 3. llama-server Deployment Model
**Claimed:** "Zephyr uses systemd llama-server services instead of K8s"
**Actual:** ALL llama-server instances are K8s Deployments
**Status:** ❌ Incorrect

**Evidence:**
```bash
# All llama-server are in K8s:
ai-inference/llama-server-sentry-59bbf8fb49-cqbf6    → sentry
ai-inference/llama-server-zephyr-3060ti-7b98646585 → zephyr
ai-inference/llama-server-zephyr-58cc45d546-s5gq9  → zephyr

# No systemd services found:
systemctl is-enabled llama-server@1237 → not-found
```

### 4. Monitoring Distribution
**Claimed:** "Nexus is now the single observability hub" / "Disabled on sentry"
**Actual:** Monitoring split between Nexus AND Sentry
**Status:** ❌ Incorrect

**Actual Distribution:**

| Service | Nexus (ai-inference ns) | Sentry (monitoring ns) |
|---------|------------------------|------------------------|
| Prometheus | ✅ Running | ✅ Running |
| Grafana | ✅ Running | ✅ Running |
| Loki | ❌ | ✅ Running |
| Mimir | ❌ | ✅ Running |
| Tempo | ❌ | ✅ Running |

### 5. Gateway Endpoints
**Claimed:** Multiple endpoints listed (/search, /search/hybrid, /rag/search, etc.)
**Actual:** Gateway health returns 200, but specific endpoints NOT verified
**Status:** ⚠️ Unverified - needs endpoint testing

**Verified:**
- ✅ Gateway healthy: `{"status":"healthy","gateway":{"version":"2.0.0"}}`
- ✅ Backend connected: `llama-server-zephyr.ai-inference.svc.cluster.local:1235`
- ✅ Knowledge Fabric middleware: `MIDDLEWARE__KNOWLEDGE_FABRIC__ENABLED=true`

### 6. brain.lan DNS
**Claimed:** "Added brain.lan entry pointing to Nexus"
**Actual:** ✅ Exists and correct
**Status:** ✅ Verified

```bash
local-data: "brain.lan. IN A 10.1.1.120"
ingress: knowledge-fabric-api → brain.lan (via Caddy)
```

### 7. Service ClusterIPs
**Claimed:** Various ClusterIPs listed
**Actual:** Mostly correct, with minor discrepancies

| Service | Claimed | Actual | Status |
|----------|---------|-------|--------|
| AI Gateway | 10.15.67.242 | 10.15.67.242 | ✅ |
| Qdrant | 10.5.93.32 | 10.5.93.32 | ✅ |
| Knowledge Fabric | 10.6.31.109 | 10.6.31.109 | ✅ |
| SearXNG | 10.4.98.141 | 10.4.98.141 | ✅ |
| Valkey | — | 10.244.1.2 | ✅ |
| Vane | — | 10.244.1.13 | ✅ |

---

## Documentation Corrections Required

### INFRASTRUCTURE-AUDIT.md

**Line ~99:** "Zephyr uses systemd llama-server services instead of K8s"
- **Correction:** All llama-server instances run as K8s Deployments

**Line ~87:** "Disabled Prometheus/Grafana/Loki on sentry"
- **Correction:** Monitoring split - full observability stack on Sentry, Prometheus+Grafana also on Nexus

**Line ~65:** "66 pods running across 23 namespaces"
- **Correction:** 66 pods running across 22 namespaces

### AGENTS.md

**Line ~84:** llama-server listed in kubernetes modules
- **Note:** This is correct, but references to systemd elsewhere are wrong

### CLAUDE.md

**Line ~752-756:** "Zephyr RTX 3090 | ✅ Systemd"
- **Correction:** All are K8s Deployments, not systemd

### ROADMAP.md

**Line ~216:** "CoreDNS, Calico running"
- **Correction:** CoreDNS, Flannel running (Calico planned but not deployed)

---

## Verified Correct Claims

✅ AI Gateway healthy (version 2.0.0)
✅ Qdrant running (10.5.93.32:6333)
✅ Knowledge Fabric middleware enabled
✅ SearXNG running (10.4.98.141:8080)
✅ Valkey/Vane running on Nexus
✅ DNS entries configured (ai-inference.lan, brain.lan, search.lan)
✅ Flannel CNI (VXLAN, UDP 8472)
✅ 66 total pods
✅ Sovereign Service Mesh architecture (bus-style)

---

## Recommendations

1. **Update llama-server references** — Remove all mentions of systemd llama-server, clarify K8s-only deployment
2. **Clarify monitoring split** — Document dual Prometheus/Grafana deployment
3. **Verify gateway endpoints** — Test /search, /search/hybrid, /rag/search endpoints
4. **Add verification script** — Create automated verification for documentation claims
5. **Version stamp docs** — Add "last verified" timestamps with commit hashes

---

**Generated:** 2026-04-24
**Verification Method:** kubectl queries, systemd checks, DNS inspection
**Confidence Level:** High (direct cluster inspection)
