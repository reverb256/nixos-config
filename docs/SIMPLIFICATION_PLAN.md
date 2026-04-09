# Documentation Simplification Plan

**Goal:** Reduce 242 docs (2.8MB) to ~50 docs (500KB) without losing information

**Date:** 2026-03-31

---

## Analysis

| Category | Count | Action | Target |
|----------|-------|--------|--------|
| Daily status/audit files | 135 | Consolidate to weekly | 12 |
| Completed plans | 12 | Archive or delete | 0 |
| Old incidents (resolved) | 10 | Summarize | 1 |
| Duplicate topics | 15 | Merge | 5 |
| Active/reference docs | 70 | Keep | 70 |
| **TOTAL** | **242** | | **~88** |

---

## Phase 1: Consolidate Status/Audit Files (135 → 12)

### Pattern: `*status-check-YYYY-MM-DD-HHMM.md`

**Action:** Merge daily files into weekly summaries

```bash
# Before: 135 daily files
docs/operations/status-check-2026-03-21-1112.md
docs/operations/status-check-2026-03-21-1500.md
docs/operations/status-check-2026-03-21-1850.md
docs/incidents/2026-03-21/comprehensive-status-report-2026-03-21.md
docs/incidents/2026-03-21/final-status-report-2026-03-21-1820.md
# ... 130 more

# After: 12 weekly files
docs/status/2026-03-week-4.md
docs/status/2026-03-week-5.md
# ...
```

**Preserve:** Key decisions, changes, issues
**Discard:** Routine status output, timestamps

---

## Phase 2: Archive Completed Plans (12 → 0)

### These plans are implemented - delete or move to archive

```
docs/plans/2026-03-20-k8s-mining-migration-design.md
docs/plans/2026-03-22-caddy-ingress-design.md
docs/plans/2026-03-22-caddy-ingress-migration.md
docs/plans/2026-03-22-caddy-ingress-implementation.md
docs/plans/2026-03-22-xmrig-intelligent-autoscaling-design.md
docs/plans/2026-03-22-xmrig-intelligent-autoscaling-implementation.md
docs/plans/2026-03-24-network-integration-design.md
docs/plans/2026-03-24-network-integration-implementation.md
docs/plans/2026-03-28-networking-security-hardening.md
docs/compute-workload-monitor-implementation-plan.md
docs/vllm-deployment-plan.md
```

**Action:** Keep only the CHANGELOG summary, delete individual plans

---

## Phase 3: Consolidate Incident Reports (16 → 3)

### Keep only major incidents with lessons learned

**Keep:**
- `docs/incidents/zombie-pod-crisis-2026-03-21.md` (Major incident)
- `docs/incidents/kube-apiserver-outage-2026-03-22.md` (If exists)
- `docs/incidents/SUMMARY.md` (Create this)

**Delete/Merge:**
- All `docs/incidents/2026-03-21/` daily status files → Merge into SUMMARY.md
- All `docs/incidents/2026-03-2*/` subdirectories

---

## Phase 4: Merge Duplicate Topics

### Kubernetes docs (105 → 30)

**Merge these into single docs:**

| Target | Source Files |
|--------|--------------|
| `docs/kubernetes/setup.md` | All *setup*, *installation*, *phase1* files |
| `docs/kubernetes/networking.md` | All *networking*, *calico*, *bgp* files |
| `docs/kubernetes/security.md` | All *security*, *rbac*, *pod-security* files |
| `docs/kubernetes/storage.md` | All *storage*, *pvc*, *garage* files |
| `docs/kubernetes/troubleshooting.md` | All *troubleshooting*, *debug*, *issue* files |

**Delete:** 70+ individual status/check/audit files

---

## Phase 5: Clean Archive (17 → 5)

**Keep truly historical:**
- Design documents with architectural decisions
- Major incident reports (already in incidents/)
- Migration completion reports

**Delete:**
- Old audit files (superseded by newer docs)
- Obsolete troubleshooting (superseded by current docs)
- Duplicate status reports

---

## Execution Order

1. **Create summaries first** (don't delete yet)
2. **Verify summaries contain key info**
3. **Delete original files**
4. **Update DOCUMENTATION_INDEX.md**
5. **Test: All references resolve**

---

## Quick Wins (Do First)

```bash
# Delete obvious duplicates (safe)
rm docs/audit/system-audit-report-*.md  # Superseded by docs/CHANGELOG.md
rm docs/incidents/2026-03-21/status-*.md  # Duplicate of main status

# Consolidate weekly status
mkdir -p docs/status
# Create weekly summaries from daily files

# Delete completed plans (already in CHANGELOG)
rm docs/plans/2026-03-*.md
```

---

## Success Metrics

- [ ] Docs reduced from 242 to <100 files
- [ ] Size reduced from 2.8MB to <1MB
- [ ] All key information preserved
- [ ] DOCUMENTATION_INDEX.md updated
- [ ] No broken references
- [ ] Can find info in <3 clicks

---

## Tools to Use

```bash
# Find duplicate content
find docs -name "*.md" -exec grep -l "same content" {} \;

# Find old dated files
find docs -name "*2026-03-2*.md" | wc -l

# Create summary
# Manual: Read files, extract key info, write summary
# Automated: Use LLM to summarize and merge
```
