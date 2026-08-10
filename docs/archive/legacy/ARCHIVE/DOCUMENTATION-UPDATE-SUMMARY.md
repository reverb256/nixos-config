# Documentation Update Summary — 2026-04-24

## Overview

Updated all cluster documentation to reflect the current state of the infrastructure, including the operational Sovereign Service Mesh with AI Gateway as the central bus.

## Files Updated

### 1. `/etc/nixos/INFRASTRUCTURE-AUDIT.md`
**Changes:**
- Updated cluster overview with current node status (Unknown vs Ready)
- Added complete Sovereign Service Mesh section with all components
- Updated service distribution table
- Added Phase 7 completion (Sovereign Service Mesh)
- Updated remaining issues and next steps

**Key Additions:**
- AI Gateway details (ClusterIP: 10.15.67.242:8080)
- RRF middleware configuration
- Mesh components table with status
- Documentation references

### 2. `/etc/nixos/ROADMAP.md`
**Changes:**
- Updated Executive Summary to reference Sovereign Service Mesh
- Added complete "Sovereign Service Mesh (2026-04-24)" section
- Updated Last Updated date
- Added architecture diagram
- Added implementation phases (0-3)

**Key Additions:**
- Bus-style architecture diagram
- Mesh components table
- Implementation phases with checkboxes
- Documentation references

### 3. `/etc/nixos/CLAUDE.md`
**Changes:**
- Replaced "AI Inference Gateway" section with "Sovereign Service Mesh — AI Gateway (Central Bus)"
- Added complete endpoint listing
- Added RRF middleware configuration
- Removed outdated backend configuration
- Added architecture description

**Key Additions:**
- Gateway endpoints table
- RRF middleware configuration YAML
- Architecture description
- Link to SOVEREIGN-SERVICE-MESH-STATUS.md

### 4. `/etc/nixos/AGENTS.md`
**Changes:**
- Updated Nexus role description to include AI Gateway
- Updated K3s status line
- Added AI Gateway status line

**Key Additions:**
- AI Gateway ClusterIP reference
- Sovereign Service Mesh operational status

### 5. `/etc/nixos/kubernetes/modules/ai-inference.nix`
**Changes:**
- Fixed Knowledge Fabric API image from `nginx:alpine` to `python:3.12-slim`
- Fixed Knowledge Fabric API port from 8081 to 3000
- Fixed Knowledge Fabric service port from 8081 to 3000
- Fixed Knowledge Fabric ingress port from 8081 to 3000
- Updated Knowledge Fabric resources (50m CPU, 64Mi memory)

### 6. `/home/j_kro/.hermes/config.yaml`
**Changes:**
- Updated provider from `ai-gateway` to `openai-compatible`
- Updated base_url from `http://127.0.0.1:1235/v1` to `http://10.15.67.242:8080/v1`

### 7. `/etc/nixos/docs/SOVEREIGN-SERVICE-MESH-STATUS.md` (NEW)
**Created:** Comprehensive status report for the Sovereign Service Mesh
**Contents:**
- Executive summary
- Mesh components status table
- Gateway endpoints listing
- Knowledge Fabric middleware configuration
- DNS configuration
- Integration status
- Next actions (priority ordered)
- Architecture diagram
- Implementation progress
- Risk assessment

### 8. `/etc/nixos/modules/network/cluster-dns.nix`
**Previous Changes (from earlier session):**
- Added aiGateway host entry
- Added clusterServices DNS entries for ai-inference.lan
- Added brain.lan entry pointing to Nexus

## Current Infrastructure State

### Sovereign Service Mesh
**Status:** ✅ OPERATIONAL

| Component | Status | ClusterIP | Node |
|-----------|--------|-----------|------|
| AI Gateway | ✅ Running | 10.15.67.242:8080 | nexus |
| Qdrant | ✅ Running | 10.5.93.32:6333 | nexus |
| Knowledge Fabric API | ✅ Running | 10.6.31.109:3000 | nexus |
| SearXNG | ✅ Running | 10.4.98.141:8080 | nexus |
| Valkey | ✅ Running | — | nexus |

### K8s Cluster
**Status:** ✅ FUNCTIONAL

- 66 pods running across 23 namespaces
- 59 Running, 7 Succeeded (completed jobs)
- 4 nodes (zephyr, nexus, forge, sentry)
- K3s v1.34.5+k3s1

### Service Distribution
**Nexus** (46GB RAM) — Primary server for:
- AI Gateway (central bus)
- Qdrant (vector DB)
- Knowledge Fabric API
- SearXNG (web search)
- Valkey/Vane (cache)
- Monitoring (Prometheus, Grafana)

**Zephyr** (31GB RAM) — Workstation for:
- Control plane
- llama-server (RTX 3090, RTX 3060 Ti)
- Mining
- Gaming

**Forge** (15GB RAM) — GPU computing for:
- Multi-GPU mining (2x NVIDIA + 2x AMD)

**Sentry** (31GB RAM) — Monitoring for:
- llama-server (AMD RX 5600 XT)
- Full observability stack (Loki, Mimir, Tempo, Grafana)

## Next Steps

### P0 — Critical
1. Restart Hermes Agent to pick up new gateway configuration
2. Test Hermes → AI Gateway integration with Knowledge Fabric middleware
3. Verify RRF integration (SearXNG + Qdrant fusion)

### P1 — High Value
4. Implement `/v1/search` unified wrapper (Phase 1.1)
5. Implement `/v1/knowledge/commit` and `/v1/knowledge/query` endpoints (Phase 1.2-1.3)
6. Wire omp to gateway (Phase 3.1)

### P2 — Medium Value
7. Phase 0: Kill pi (audit and remove redundant tool stack)
8. Model role routes: `/v1/chat/smol|slow|plan` (Phase 1.4)
9. Knowledge ingestion pipeline (auto-commit from SearXNG results)

## Documentation References

- **Sovereign Service Mesh Plan:** `/etc/nixos/.hermes/plans/2026-04-22_sovereign-service-mesh.md`
- **Service Mesh Status:** `/etc/nixos/docs/SOVEREIGN-SERVICE-MESH-STATUS.md`
- **Knowledge Fabric Reflow:** `/etc/nixos/docs/KNOWLEDGE-FABRIC-REFLOW.md`
- **Hermes Pipelines Research:** `/etc/nixos/docs/hermes-pipelines-research.md`

---

**Generated:** 2026-04-24
**Commit:** Pending
**Branch:** main
