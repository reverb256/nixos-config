# Issue #5: cargo check on cachix fork

**Priority:** HIGH  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** `secretspec-fork-patches/0001-add-sops-provider.patch` was generated based on syntax-correct sources, but was NEVER compiled. Drift-cycle closure (and the entire Option-B auto-couple architecture) assumes the fork builds.  
**Depends on:** none  
**Blocks:** Issue #6 (push upstream PR + confirm cachix CI accepts the patch).

## Context

Throughout this session, "syntax-correct" was used to describe the patch's Rust source. But Rust compilation has additional constraints beyond syntax: crate imports, feature-flag wiring, type compatibility with the parent secretspec-derive crate, lints. None of these were checked. If `cargo check` fails, the entire Option-B architecture rests on unverified ground.

## Acceptance Criteria

- `cd ~/Projects/secretspec-core && cargo check --all-features` exits 0.
- If exit non-zero, capture the errors and update the patch series. Repeat until green.

## Approach

1. `cd ~/Projects/secretspec-core`. Ensure `feature/sops-provider-subprocess-dispatch` branch is checked out.
2. `cargo clean` (only if cache might be stale).
3. `cargo check --all-features --offline` initially (uses cached deps); if not, `cargo check --all-features` (downloads if needed).
4. Capture all output to `/tmp/cargo-check-$(date).log`.
5. If errors: check for common issues (missing `tokio/process` impl in `sops.rs`, feature name mismatches, etc.) — patch and re-run.

## Risk

- The cachix fork is older and may interact poorly with current rust toolchain (Lix 2.95.2). Rust-version mismatch is the most likely failure mode.
- If `cargo check` fails repeatedly, escalate: maybe the patch needs a different shape (e.g., feature-gated sops module differently).

## Related

- `pkgs/secretspec/default.nix` header comment
- `secretspec-fork-patches/0001-add-sops-provider.patch`
- Issue #6 (subsequent upstream PR)
