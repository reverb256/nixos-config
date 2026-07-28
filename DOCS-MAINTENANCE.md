# DOCS-MAINTENANCE.md

# Documentation Maintenance Policy

**Last Audited**: 2026-07-27

> Recent audit: [`docs/audit-2026-07-27.md`](docs/audit-2026-07-27.md) — 24 findings, F-21/F-22/F-23 directly address doc-drift hygiene.

This living document enforces hygiene for all Markdown files in the sovereign AI stack.

## Stale Banner Template (add to top of outdated docs)
```markdown
> ⚠️ **OUTDATED** — Last updated YYYY-MM-DD. See [DOCS-MAINTENANCE.md](DOCS-MAINTENANCE.md) for current practices.
```

## Rules
- Every .md file must have YAML frontmatter with `last_updated` and `status`
- Kagent auto-flags files >30 days untouched
- Quarterly full audits required
- AGENTS.md is source of truth for workflows
- **Pocock Rule (from `knowledge.md`, §Doc-rot prevention):** every doc must carry a `Last Verified` date. Any doc >7 days stale must be re-verified against cluster state before being followed. The 2026-07-27 audit enforced this orbit-wide — see `docs/audit-2026-07-27.md` findings F-21 (STATUS/RUNBOOK stale >2mo), F-22 (INFRASTRUCTURE-AUDIT 71-day drift), F-23 (CODE_DEPRECATIONS frozen since 2026-04-15).

## Current Status
- nixos-config: Partial compliance (see `docs/audit-2026-07-27.md` for current compliance gap inventory)
- maplespike: Needs consolidation

### Doc hygiene observations from 2026-07-27 audit
- 3 docs were carrying 1-3 month-old "last verified" stamps and instructions that conflict with current code (`docs/LIVE/STATUS.md`, `docs/LIVE/RUNBOOK.md`, `INFRASTRUCTURE-AUDIT.md`).
- `docs/CODE_DEPRECATIONS.md` is mechanically frozen — most entries predate the 2026-04-07 K3s migration and the 2026-05-14 forward_auth rewrite. Recommend a full recount from `rg -n 'DISABLED|TEMPORARILY' --glob '*.nix'` once per release-train (currently quarterly per this policy).
- `ROADMAP.md` line-3 header flags itself as stale; pointer to `INFRASTRUCTURE-AUDIT.md` remains correct but should now also point to `docs/audit-2026-07-27.md`.

Kagent will enrich this file periodically.