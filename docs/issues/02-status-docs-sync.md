# Issue #2: Status docs sync (STATUS.md / INFRASTRUCTURE-AUDIT.md / SOPS-NIX.md)

**Priority:** MED  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** Drift-cycle Option-B implementation never reflected in operator-facing records  
**Depends on:** none  
**Blocks:** contributor documentation accuracy

## Context

Three operator-facing status documents exist at the repo root: `STATUS.md` (auto-generated hourly by status-update.timer), `INFRASTRUCTURE-AUDIT.md` (the 2026-07-03 audit remediation plan), and `SOPS-NIX.md` (sops-nix usage guide). None of them mention the Option-B drift-cycle implementation that shipped 2026-07-25 — meaning future maintainers/agents consulting these docs get an outdated picture.

Verification via `rg 'cluster.localSealSupport|option B|sops-registry.enable or false'` against all three returns 0 matches: the new architecture is invisible at the operator-docs layer.

## Acceptance Criteria

- Each of the three status-docs has a section/changelog entry noting the Option-B drift-cycle implementation date.
- Cross-reference from each doc to `.plans/2026-07-25-cluster-localSealSupport-scope.md` (the canonical source).
- `STATUS.md` regenerates without losing the new info (the auto-update script must not clobber Option-B note).

## Approach

1. For each file, add a section: `## Drift Cycle 2026-07-25` with:
   - Note about Option-B implementation (cluster.localSealSupport auto-couple).
   - Cross-reference to the plan doc.
   - Note about coupling-required for any host-config touching validator or sops-registry.
2. Verify `STATUS.md` regenerates from `cluster-state.nix` properly; if not, augment the regeneration script to surface the drift-cycle state.

## Related

- `.plans/2026-07-25-cluster-localSealSupport-scope.md`
- `modules/system/secretspec-validator.nix`
- `modules/system/secretspec-cluster-mode.nix`
