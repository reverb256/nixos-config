# DOCS-MAINTENANCE.md

# Documentation Maintenance Policy

**Last Audited**: 2026-05-21

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

## Current Status
- nixos-config: Partial compliance
- maplespike: Needs consolidation

Kagent will enrich this file periodically.