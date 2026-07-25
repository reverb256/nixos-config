# Issue #10: Apply AGENTS.md / CLAUDE.md guidance to drift-cycle architecture

**Priority:** LOW  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** Wave-1 read confirmed AGENTS.md and CLAUDE.md reinforce strict-declarative + `just`-recipe workflow. The drift cycle landed multiple times with code-reviewer flagging best-practices that already exist in AGENTS.md (e.g., "Always find the .nix file first"). Future agents could be pointed at these docs more deliberately.  
**Depends on:** none  
**Blocks:** contributor onboarding

## Context

Two cluster-specific guidance documents: `AGENTS.md` (operational rules + workflow) and `CLAUDE.md` (model-specific overrides + critical safety rules). Both reached mid-session in reads, but apply uniformly to the drift-cycle decisions.

Key takeaways from Wave-1 read (relevant refrains):
- Strictly declarative only (`nix` files, not `nix-env -iA` aka imperatively installing).
- Live hosts are consumers, never source-of-truth.
- Use `just` recipes (`just check`, `just switch`, `just deploy`, etc.).
- Use `mkOptionDefault` for extensible attrs (avoid breaking SSH cluster-wide on a typo).

## Acceptance Criteria

- knowledge.md gets a "Cluster Guidance" section cross-referencing AGENTS.md + CLAUDE.md.
- Drift-cycle-history table (plan doc) row for "Drift Cycle Corrections" notes "follows AGENTS.md strict-declarative rule by writing through .nix files; mkOptionDefault used wherever applicable".
- Justfile recipes used during drift cycle are all declarative (verified).
- knowledge.md knowledge.md "Operational gotchas" section now mentions AGENTS.md and CLAUDE.md.

## Approach

1. Verify all drift-cycle edits followed AGENTS.md/CLAUDE.md rules (audit pass on commit history via `git log`).
2. Update knowledge.md "Cluster Guidance" subsection.
3. Update plan doc Drift Cycle History table footnote.

## Risk

Low. Documentation-only task.

## Related

- AGENTS.md
- CLAUDE.md
- knowledge.md
- `.plans/2026-07-25-cluster-localSealSupport-scope.md`
