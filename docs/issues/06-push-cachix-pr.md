# Issue #6: Push cachix/secretspec PR for sops Provider module

**Priority:** HIGH (long-lead)  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** The drift-cycle architecture (Option B) is a workaround for the upstream cachix/secretspec not having a sops:// provider. Once cachix merges our patch series (cachix/secretspec#98 reference), the entire cluster-side scaffolding (`cluster.localSealSupport`, `--option pure-eval false` flags, local-fork checkout) becomes unnecessary.  
**Depends on:** Issue #5 (cargo check on cachix fork must pass first).  
**Blocks:** Option C migration (Issue #8-equivalent in `.plans/` + plan-doc archival).

## Context

The patch adds `provider/sops.rs` + `register_provider!` macro registration + `pub mod sops` in `provider/mod.rs` gated on `#[cfg(feature = "sops")]`. This is the artifact cachix maintainers would need to merge to ship sops support to all secretspec users, not just our fork-consumers.

## Acceptance Criteria

- `gh pr create --repo cachix/secretspec --base main --head feature/sops-provider-subprocess-dispatch` exits 0.
- PR URL captured for tracking.
- PR description frames the sops:// provider as a Protocol v1 subprocess dispatch (per cachix/secretspec#98 reference in the existing secretspec.toml).

## Approach

1. Verify Issue #5 (cargo check) shows green compilation.
2. Update cachix fork README/CHANGELOG to document the new sops feature.
3. Push the cachix fork branch (currently local) to cachix/secretspec: `gh pr create --repo cachix/secretspec --head feature/sops-provider-subprocess-dispatch --title "feat(provider): add SOPS via Secret Provider Protocol (issue #98)" --body-file secretspec-fork-patches/PR-DESCRIPTION.md` (might need to template the body first).
4. Watch cachix CI; address any reviewer feedback.
5. After merge + cachix release (v0.17.0+ presumably): update `pkgs/secretspec/default.nix` to fetch from upstream instead of fork.

## Estimated Timeline

- Operator-side: 1 hour
- Cachix maintainer review: variable, typically 1-4 weeks for meaningful PRs

## Related

- cachix/secretspec#98 (the upstream issue this addresses)
- `secretspec-fork-patches/0001-add-sops-provider.patch`
- `.plans/2026-07-25-cluster-localSealSupport-scope.md` Stream 7
