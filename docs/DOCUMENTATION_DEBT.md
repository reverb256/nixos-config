# Documentation Debt Backlog

**Created:** 2026-04-02 | **Owner:** Sisyphus (AI Agent) | **Status:** Active

This document tracks documentation debt items identified during the 2026-04-02 audit. Each item includes severity, owner assignment, and target resolution date.

---

## Prioritized Backlog

### P0 - Critical (This Sprint)

| ID | Item | Location | Severity | Owner | Target |
|----|------|----------|----------|-------|--------|
| DOC-001 | Duplicate STATUS blocks causing confusion | `STATUS.md`, multiple docs | 🔴 Critical | - | 2026-04-05 |
| DOC-002 | Missing auto-generation for STATUS.md | `STATUS.md` | 🔴 Critical | - | 2026-04-05 |
| DOC-003 | Outdated ROADMAP claims vs actual K8s version | `ROADMAP.md` | 🔴 Critical | - | 2026-04-05 |

### P1 - High (This Month)

| ID | Item | Location | Severity | Owner | Target |
|----|------|----------|----------|-------|--------|
| DOC-004 | Date-stamped reference docs violate conventions | `DOCUMENTATION_AUDIT_*.md` | 🟠 High | - | 2026-04-15 |
| DOC-005 | Multiple docs reference deprecated components | Various `docs/kubernetes/` | 🟠 High | - | 2026-04-15 |
| DOC-006 | Unclear deployment workflow (NFS vs Colmena) | `README.md`, `modules/README.md` | 🟠 High | - | 2026-04-15 |
| DOC-007 | Missing "Purpose" lines in DOCUMENTATION_INDEX | `DOCUMENTATION_INDEX.md` | 🟠 High | - | 2026-04-15 |

### P2 - Medium (This Quarter)

| ID | Item | Location | Severity | Owner | Target |
|----|------|----------|----------|-------|--------|
| DOC-008 | Inconsistent naming in script documentation | `scripts/` | 🟡 Medium | - | 2026-05-01 |
| DOC-009 | Missing changelog for recent changes | `docs/CHANGELOG.md` | 🟡 Medium | - | 2026-05-01 |
| DOC-010 | Some docs have no "Last Updated" timestamp | Various | 🟡 Medium | - | 2026-05-01 |
| DOC-011 | Duplicate content across docs (brightness control, MCP) | `docs/brightness-control-setup.md`, `docs/kubernetes/MCP_*.md` | 🟡 Medium | - | 2026-05-01 |

### P3 - Backlog (Future)

| ID | Item | Location | Severity | Owner | Target |
|----|------|----------|----------|-------|--------|
| DOC-012 | No dedicated incident template | `docs/incidents/` | 🔵 Low | - | TBD |
| DOC-013 | Missing glossary of terms | `docs/` | 🔵 Low | - | TBD |
| DOC-014 | API documentation scattered | `modules/services/*` | 🔵 Low | - | TBD |

---

## Resolved Items

| ID | Item | Resolved | Notes |
|----|------|----------|-------|
| DOC-R01 | Duplicate status in multiple files | 2026-04-02 | Consolidated to single STATUS.md source |
| DOC-R02 | Outdated changelog entries | 2026-04-02 | Updated in previous cleanup |

---

## Quick Fix Commands

### Check for duplicates
```bash
# Find date-stamped docs that shouldn't be dated
rg -l '\d{4}-\d{2}-\d{2}' docs/*.md

# Find docs missing Last Updated
rg -L 'Last Updated' docs/*.md

# Find deprecated markers
rg -l '❌ Deprecated|DEPRECATED|OBSOLETE' docs/
```

### Generate current status
```bash
just cluster-status  # Updates STATUS.md
```

---

## Related Files

- `DOCUMENTATION_CONVENTIONS.md` - Documentation style guide
- `DOCUMENTATION_INDEX.md` - Master catalog
- `DOCUMENTATION_AUDIT_SUMMARY.md` - Previous audit results
- `STATUS.md` - Real-time cluster status

---

**Note:** This file should be updated whenever new documentation debt is identified. Use the ID format `DOC-###` for new items.
