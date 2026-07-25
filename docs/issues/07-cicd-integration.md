# Issue #7: CI/CD integration — workflow + pre-commit + nixos-integration test

**Priority:** HIGH (prevents drift regression)  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** User explicitly asked "add steps in ci/cd" mid-session. Never delivered. Pre-commit hooks for secretspec-related checks never wired. nixos-integration test for cluster.localSealSupport coupling never written.  
**Depends on:** none  
**Blocks:** future drift cycle regressions

## Context

The drift cycle closure was a multi-session effort. The clusterside state is fragile in two ways:
- Future PRs to `pkgs/secretspec/default.nix` or `modules/system/secretspec-cluster-mode.nix` could re-introduce the bug (silent fallback to upstream tarball).
- Future host-configs that disable `sops-secrets-registry` while enabling `secretspec-validator` could eval-error via the `?`-test.

No automation captures this. New contributors reading the drift-cycle history can re-create the same multi-session debug cycle without noticing.

## Acceptance Criteria

- `.github/workflows/secretspec-coupling-check.yml` runs `just secretspec-validate-local` + greps for `cluster.localSealSupport`/`sops-secrets-registry.enable` consistency on every PR. Failing conditions emit PR-comment annotations.
- `.pre-commit-config.yaml` adds secretspec-validate-local + alejandra-format-on-staged + statix-check-on-staged hooks.
- `tests/secretspec-coupling.nix` runs an integration check inside NixOS test VM: import cluster-mode + secretspec-validator, verify `cluster.localSealSupport` defaults correctly with sops-registry state.
- `tests/options-consistency.nix` runs after every commit (catches option name typos — a class of bug that broke `services.syncthing-cluster` previously per zephyr config).

## Approach

1. Write `.github/workflows/secretspec-coupling-check.yml` (YAML, ~50 lines; uses `nix --extra-experimental-features nix-command build .#secretspec` + `just secretspec-validate-local` steps).
2. Update `.pre-commit-config.yaml` to add rust-style hooks that fail-fast on secretspec validate failures.
3. Create `tests/secretspec-coupling.nix`: import the modules, set `services.sops-secrets-registry.enable = true`, verify `config.cluster.localSealSupport == true` + `config.services.secretspec-validator.enable == true`. Settings `enable = false` should produce `localSealSupport == false`.
4. Update `tests/options-consistency.nix` if needed (legacy file).
5. Wire into CI via cron or pre-push triggers.

## Risk

- CI gate false-positives if regex/grep rule is wrong — start as `warn`, tighten over time.
- nixos-integration tests depend on the validator systemd unit not requiring actual secretspec.toml — test design should isolate the coupling check from runtime behavior.

## Related

- `tests/` directory (existing options-consistency.nix)
- `.github/workflows/` (existing CI)
- Module signatures (cluster-mode, validator)
