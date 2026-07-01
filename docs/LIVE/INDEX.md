---
last-verified: 2026-05-24
verified-by: Sisyphus
verification-method: just docs-audit
expires: 2026-05-31
---
# Documentation Index

## LIVE Documents (Canonical)

- [INFRASTRUCTURE-AUDIT.md](INFRASTRUCTURE-AUDIT.md) — Current cluster state, services, rules
- [ARCHITECTURE.md](ARCHITECTURE.md) — Diagrams and data flows (coming)
- [RUNBOOK.md](RUNBOOK.md) — Operational procedures (coming)
- [STATUS.md](STATUS.md) — One-page health dashboard (coming)

## Supporting

- [DOCUMENTATION-STRATEGY.md](../meta/DOCUMENTATION-STRATEGY.md) — This system's rules
- PATTERNS/ — Coding and module conventions
- DECISIONS/ — Architectural Decision Records

## Rules

- All LIVE documents must have `last-verified` stamp < 14 days old.
- Run `just docs-audit` before every merge.
- If cluster changes, update LIVE documents in same PR.
- Stale documents belong in ARCHIVE/.

**Never edit files outside LIVE/ for current state.**
