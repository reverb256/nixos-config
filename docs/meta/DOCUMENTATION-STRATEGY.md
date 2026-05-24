# Long-term Documentation Strategy

**Last Verified:** 2026-05-24  
**Verified By:** Sisyphus (commit pending)  
**Expires:** 2026-06-07

## Principles

1. **Reality > Documentation** — Running cluster state is truth. Docs must match or be marked wrong (Pocock Rule enforced).
2. **Documentation is Code** — Versioned, reviewed, tested, CI-gated.
3. **Staleness is Debt** — >14 days without verification = deprecated until refreshed.
4. **Single Source of Truth** — `docs/LIVE/` contains canonical documents. All other docs summarize or archive.
5. **Enforceable by Agents** — Rules are machine-checkable. Verification suite must pass.

## Directory Structure

```
docs/
├── LIVE/                    # Canonical, always-current documents
│   ├── INFRASTRUCTURE-AUDIT.md
│   ├── ARCHITECTURE.md
│   ├── RUNBOOK.md
│   └── STATUS.md
├── PATTERNS/                # Living conventions and templates
├── DECISIONS/               # Architectural Decision Records (ADRs)
├── RESEARCH/                # Temporary research (auto-archived after 90d)
├── ARCHIVE/                 # Superseded content
├── meta/
│   ├── DOCUMENTATION-STRATEGY.md
│   └── VERIFICATION-SUITE/  # Validation scripts
└── plans/                   # Only active plans (archived on completion)
```

## Verification System

All LIVE documents must contain:

```markdown
---
last-verified: YYYY-MM-DD
verified-by: <name> (commit abc123)
verification-method: verification-suite/run.sh --check infra
expires: YYYY-MM-DD
---
```

**Verification Suite** (`docs/meta/VERIFICATION-SUITE/`):
- `verify-infra.sh` — Compares claims vs live cluster
- `verify-staleness.sh` — Flags documents >14 days old
- `cross-reference-check.sh` — Detects contradictions
- `run.sh` — Master runner

**CI Integration**: Runs on every PR touching `docs/`, `modules/`, `hosts/`, `kubernetes/`.

## Workflow Rules

- Every infrastructure change PR **must** update affected LIVE document.
- PR template requires documentation checklist.
- `just docs-audit` must pass before merge.
- Discovered contradictions create `documentation-rot` issue.

## Implementation Status

**Phase 0** — Structure + strategy + verification suite → **COMPLETE**
**Phase 1** — Rewrite all LIVE documents with current state → **IN PROGRESS**
**Phase 2** — Full CI integration and agent training → Pending

This document is the root of all documentation policy. All other docs must comply with it.
