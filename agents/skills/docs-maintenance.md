# Keeping documentation fresh (Pocock Rule)

**Last verified:** 2026-08-16

Planning documents are living documents. If reality has diverged from a plan
doc, the plan is wrong — not reality.

## Rules

1. Every plan doc (`docs/plans/*.md`) must have a `Last Verified` date header.
2. Before following any plan, check it was verified within 7 days. If not,
   re-verify against current cluster state first.
3. After completing work described in a plan, update it with actual outcomes.
4. Stale plans (>14 days) should be flagged, not followed blindly.
5. If you spot a wrong section in `AGENTS.md`, fix it immediately.

## Maintained-document contract

`docs/meta/VERIFICATION-SUITE/ACTIVE-DOCUMENTS.txt` is the explicit manifest of
maintained docs. Each entry must exist and carry a `Last Verified` date within
`DOC_MAX_AGE_DAYS` (default 7). Historical reports and archives stay out of the
manifest.

## Verify

```bash
just docs-audit       # runs docs/meta/VERIFICATION-SUITE/run.sh
                      # (staleness + source-of-truth + internal links)
just docs-freshen     # same suite, with operator guidance
```
