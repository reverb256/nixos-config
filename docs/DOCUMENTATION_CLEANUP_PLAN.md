# Documentation Cleanup & Consolidation Plan

**Date:** 2026-03-16
**Status:** Ready for Review
**Priority:** HIGH

---

## Executive Summary

Found **significant documentation sprawl** with 9 storage-related files, 3 HA files with conflicting information, and multiple "quick wins" that remain pending. This plan consolidates documentation and removes obsolete files.

---

## Critical Issues Found

### 1. Incorrect HA Documentation

| File | Issue | Action |
|------|-------|--------|
| `docs/kubernetes/ha-implementation-guide.md` | Documents HAProxy layer that was never implemented | **ARCHIVE** - Mark as obsolete, Keepalived VIP used instead |
| `docs/kubernetes/ha-deployment-checklist.md` | References HAProxy implementation guide | **ARCHIVE** - Depends on obsolete guide |
| `docs/kubernetes/control-plane-architecture.md` | Correct - documents Keepalived VIP only | **KEEP** - This is accurate |

**Root Cause:** HAProxy was planned but actual implementation used Keepalived VIP directly without HAProxy layer.

---

### 2. Incorrect Storage Documentation

| File | Issue | Action |
|------|-------|--------|
| `docs/storage-architecture.md` | Claims "3-node distributed cluster" with "3-way replication" | **ARCHIVE** - Actual config: `replicationFactor = 1` |
| `docs/kubernetes/storage/storage-architecture.md` | Correct - single-node Garage | **KEEP** - This is accurate |
| `docs/storage-configuration.md` | May contain outdated Garage cluster info | **REVIEW** |
| `docs/storage-status-verified-2026-03-13.md` | Status report - likely outdated | **ARCHIVE** |
| `docs/storage-cluster-status-report.md` | Status report - may be outdated | **ARCHIVE** |
| `docs/storage-unified-architecture-plan.md` | Contains deprecated service reference | **REVIEW** |
| `docs/plans/2026-03-12-cluster-storage-*.md` (2 files) | Implementation plans | **ARCHIVE** - Completed work |
| `docs/storage-test-results-2026-03-13.md` | Test results | **ARCHIVE** - Historical |

**Root Cause:** Storage architecture was simplified from planned 3-node to actual single-node, but old docs never updated.

---

### 3. Gateway "Quick Wins" Still Pending

From `docs/gateway/gateway-improvement-roadmap.md`:

| Quick Win | Date Added | Status | Effort |
|-----------|------------|--------|--------|
| Remove debug logs | 2026-03-04 | **PENDING** | 1 hour |
| Update README.md | 2026-03-04 | **PENDING** | 2 hours |

**Issue:** Labeled "quick wins" but not completed after 12+ days.

---

### 4. Dropped/Planned Features Never Implemented

| Phase | Planned Feature | Status | Notes |
|-------|-----------------|--------|-------|
| ROADMAP Phase 3 | Stateful Services Migration | ⏳ Not Started | GlitchTip DB migration |
| ROADMAP Phase 4 | Stateless Services Migration | 🟡 5% Started | Only Caddy Ingress |
| ROADMAP Phase 5 | GPU Workloads Migration | ⏳ Not Started | AI services still systemd |
| ROADMAP Phase 7 | Cleanup & Optimization | ⏳ Not Started | Remove old systemd services |
| Gateway Phase 1 | Health Check Implementation | ⏳ Not Started | TODO at line 272 |

---

## Recommended Actions

### Immediate (Priority 1)

1. **Archive incorrect storage documentation:**
   ```bash
   mkdir -p docs/archive/obsolete/storage
   mv docs/storage-architecture.md docs/archive/obsolete/storage/storage-architecture-incorrect.md
   mv docs/storage-status-verified-2026-03-13.md docs/archive/obsolete/storage/
   mv docs/storage-cluster-status-report.md docs/archive/obsolete/storage/
   ```

2. **Archive incorrect HA documentation:**
   ```bash
   mkdir -p docs/archive/obsolete/kubernetes
   mv docs/kubernetes/ha-implementation-guide.md docs/archive/obsolete/kubernetes/ha-implementation-guide-haproxy-not-implemented.md
   mv docs/kubernetes/ha-deployment-checklist.md docs/archive/obsolete/kubernetes/ha-deployment-checklist-haproxy-not-implemented.md
   ```

3. **Complete Gateway "Quick Wins":**
   - Remove debug logs from `modules/services/ai-inference/ai_inference_gateway/main.py`
   - Update `modules/services/ai-inference/README.md` with accurate features

### Short-term (Priority 2)

4. **Consolidate storage documentation:**
   - Keep only `docs/kubernetes/storage/storage-architecture.md` as authoritative
   - Archive all other storage docs to `docs/archive/obsolete/storage/`
   - Update DOCUMENTATION_INDEX.md to reflect new structure

5. **Update DOCUMENTATION_INDEX.md:**
   - Remove references to archived files
   - Add notes about architectural decisions (why HAProxy wasn't used, why Garage is single-node)

### Long-term (Priority 3)

6. **Decide on stalled ROADMAP phases:**
   - Phase 3 (Stateful Services): Proceed or defer?
   - Phase 4 (Stateless Services): Continue or pause?
   - Phase 5 (GPU Workloads): Relevant given GPU marketplace?
   - Phase 7 (Cleanup): Old systemd services still running

7. **Address Gateway Phase 1 items:**
   - Implement actual health checks (line 272 TODO)
   - Document RAG/MCP capabilities accurately

---

## File Status Matrix

| File | Action | Destination | Reason |
|------|--------|-------------|--------|
| `docs/kubernetes/ha-implementation-guide.md` | ARCHIVE | `archive/obsolete/kubernetes/` | HAProxy not implemented |
| `docs/kubernetes/ha-deployment-checklist.md` | ARCHIVE | `archive/obsolete/kubernetes/` | Depends on obsolete guide |
| `docs/kubernetes/control-plane-architecture.md` | KEEP | - | Accurate, Keepalived VIP |
| `docs/storage-architecture.md` | ARCHIVE | `archive/obsolete/storage/` | Incorrect replication claims |
| `docs/kubernetes/storage/storage-architecture.md` | KEEP | - | Accurate, single-node |
| `docs/storage-configuration.md` | REVIEW | - | Verify accuracy |
| `docs/storage-status-*.md` | ARCHIVE | `archive/obsolete/storage/` | Outdated status reports |
| `docs/plans/2026-03-12-cluster-storage-*.md` | ARCHIVE | `archive/completed-plans/` | Implementation completed |
| `docs/storage-test-results-2026-03-13.md` | ARCHIVE | `archive/obsolete/storage/` | Historical test results |

---

## Decision Points

### 1. HAProxy vs Keepalived VIP

**Question:** Was HAProxy intentionally skipped in favor of simpler Keepalived VIP?

**Impact:** If HAProxy is needed eventually, we need new implementation docs.

**Recommendation:** Document why Keepalived VIP was chosen (simpler, sufficient for 3-node cluster).

### 2. Garage Replication Factor

**Question:** Should Garage be expanded back to 3-way replication?

**Current State:** `replicationFactor = 1` (single-node mode in `modules/services/akash-provider.nix:414`)

**Trade-offs:**
- Single-node: Simpler, less storage overhead, no quorum issues
- 3-way: Better durability, requires 3 nodes, more complexity

**Recommendation:** Keep single-node unless durability requirements change.

### 3. Kubernetes Migration Phases

**Question:** Should ROADMAP phases 3-5 proceed or be deferred?

**Context:**
- Phase 2 (worker nodes) complete
- Phase 4 partially started (Caddy Ingress only)
- GPU Resource Marketplace deployed separately

**Recommendation:** Review if full K8s migration still aligns with goals, or if hybrid approach (systemd + K8s) is acceptable.

---

## Documentation Hygiene Recommendations

### Preventing Future Drift

1. **Date all documents** with "Last Updated" field
2. **Status indicators** on all roadmap items (Not Started / In Progress / Complete)
3. **Archive obsolete docs** - don't delete, move to `archive/obsolete/`
4. **Single source of truth** - one authoritative doc per topic
5. **Cross-reference validation** - check references when archiving

### Documentation Review Process

1. **Weekly:** STATUS.md vs ROADMAP.md reconciliation
2. **Monthly:** Full documentation audit (like this one)
3. **Post-deployment:** Update docs after any architectural change

---

## Success Criteria

- [ ] All incorrect documentation archived
- [ ] DOCUMENTATION_INDEX.md updated
- [ ] No duplicate documentation on same topics
- [ ] Gateway "quick wins" completed or removed
- [ ] ROADMAP phases updated with current status
- [ ] Decision document created for architectural choices

---

**Last Updated:** 2026-03-16
**Next Review:** 2026-04-16
