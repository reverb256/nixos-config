# Issue #0 (umbrella): Drift Cycle 2026-07-25 Closure - Phase 2/3/4 followups

**Priority:** HIGH (umbrella)  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** The drift cycle (Phase 1) closed locally with Phase 2/3/4 followups deferred. This umbrella tracks the entire post-closure wave.  
**Depends on:** nothing  
**Blocks:** Stream 7 cachix upstream PR (all of Stream 7 is contained in this umbrella's scope)

## Context

The drift cycle on `/etc/nixos` (cluster localSealSupport + impure-eval coupling) shipped 2026-07-25 with 13 Drift Cycle History rows marked ✅ landed. Subsequent inspection surfaced real concerns and followups. This umbrella tracks the post-closure wave:

- Issue #1: Cluster-wide validation verify
- Issue #2: Status docs sync
- Issue #3: knowledge.md "Other services" expansion
- Issue #4: Pin cachix fork SHA (reproducibility)
- Issue #5: cargo check on cachix fork (compiler-validation)
- Issue #6: Push cachix upstream PR (long-term, depends on #5 green)
- Issue #7: CI/CD integration (workflow + pre-commit + integration test)
- Issue #8: patches/ audit (4 broken patches)
- Issue #9: Recover gravity_index orphaned Phase-1 work
- Issue #10: AGENTS.md/CLAUDE.md guidance capture

## Acceptance Criteria

- All 10 child issues closed.
- `.plans/2026-07-25-cluster-localSealSupport-scope.md` archive-stamped.
- `STATUS.md` / `INFRASTRUCTURE-AUDIT.md` / `SOPS-NIX.md` reflect landed state.

## Approach

Execute per-order-of-easiest-first:
1. Issue #1 (cluster-wide validation) - **highest priority** because confirms the drift closure.
2. Issue #4 (pin SHA) - directly improves reproducibility.
3. Issue #5 (cargo check) - then #6 (push PR).
4. Issue #7 (CI/CD integration) - prevents regressions.
5. Documentation updates (#2, #3, #10).
6. Issue #8 (patches/) - admin cleanup.
7. Issue #9 (gravity_index recovery) - lowest priority.

## Related

- `.plans/2026-07-25-cluster-localSealSupport-scope.md` (drift cycle plan)
- All 10 child issues listed above
