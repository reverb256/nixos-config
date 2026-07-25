# Issue #4: Pin cachix fork branch SHA for reproducibility

**Priority:** HIGH  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** `pkgs/secretspec/default.nix` defines `localForkPath = /home/j_kro/Projects/secretspec-core` without pinning the cachix fork branch SHA. Future builds re-clone the same `feature/sops-provider-subprocess-dispatch` branch tip without version — drift risk.  
**Depends on:** none  
**Blocks:** Stream 7b Option-C flake-input migration (needs SHA to pin in flake.nix too).

## Context

The cachix fork is referenced by branch name. The local-fork checkout at `~/Projects/secretspec-core` is whatever `feature/sops-provider-subprocess-dispatch` HEAD was at clone time. Re-cloning yields a different commit. Builds are non-reproducible.

## Acceptance Criteria

- `pkgs/secretspec/default.nix` carries a `localForkSha` or `localForkRev` (captured via `git -C ~/Projects/secretspec-core rev-parse HEAD`) recorded in a comment + a `cleanSource` provenance field.
- Same for `pkgs/secretspec-provider-sops/default.nix` (cachix provider-rust fork SHA).
- An operator rebuilding with a fresh clone of the fork gets the same closure.

## Approach

1. `git -C ~/Projects/secretspec-core rev-parse HEAD` + `git -C ~/Projects/secretspec/provider-rust rev-parse HEAD` — capture SHAs.
2. Update the header comment in both `pkgs/*.nix` files to include the captured SHA + date.
3. Document in `knowledge.md` that re-clones from upstream will yield a different SHA, requiring manual updating of the hair.

## Related

- Stream 7a cachix upstream PR (after PR + merge, archive fork checkout)
- `.plans/2026-07-25-cluster-localSealSupport-scope.md`
