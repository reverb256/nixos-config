# Issue #3: secretspec-fork cargo check + cargo test

**Priority:** CRITICAL  \n**Status:** Open  \n**Created:** 2026-07-25  \n**Origin:** Drift-cycle Stream 2 closure, compendium item C1  \n**Depends on:** `~j_kro/Projects/secretspec-core` checkout + applied patch series  \n**Blocks:** cachix upstream PR (cannot push branch without compiler confidence) + remote
host validation (secretspec validator systemd unit must build before it can activate)

## Context

The drift-cycle was closed on the hypothesis that the local forked cachix/secretspec
(`~/Projects/secretspec-core`, branch `feature/sops-provider-subprocess-dispatch` +
applied patch `secretspec-fork-patches/0001-add-sops-provider.patch`) builds cleanly. The
patch was generated from syntax-correct sources and was inspected line-by-line, but no
`cargo check` was ever executed against the actual compiler.

Without a successful `cargo check`, **the entire drift cycle thesis is unproven**: if the
fork doesn't compile, the validator systemd unit on zephyr will fail at activation, and
Option B's auto-coupled impure-eval relaxation will have been applied across all four
hosts with no actual sops:// feature delivery. Recovering from that (reverting
`nix.settings.pure-eval = false`) is a separate flush-the-cluster patch.

## Acceptance Criteria

- `cd ~/Projects/secretspec-core && cargo check --all-features` exits 0 within ~5 min.
- `cd ~/Projects/secretspec-core && cargo test -p secretspec --features sops` exits 0
  (tests skip subprocess dispatch per `doCheck = false` in `pkgs/secretspec/default.nix`,
  but library-level tests for the `sops` module must pass).
- `cd ~/Projects/secretspec-core && cargo build -p secretspec --release --features sops`
  exits 0 (matches the `--release` profile in `pkgs/secretspec/default.nix`).
- The compiled binary, if executed manually with a temp age keypair
  (`SOPS_AGE_KEY_FILE=/tmp/key.txt sops://`), exits 0 on a smoke decrypt
  (`echo 'ENC[AES256_GCM,...]' | secretspec resolve` returning plaintext).

## Failure modes

- **Missing imports in patch.** E.g. the sops module references `secretspec_core::Provider`
  but the upstream trait isn't yet exported in the cachix/secretspec version that the
  patch was generated against. Fix: re-author patch against the latest upstream main
  (cachix/secretspec@HEAD).
- **Type errors.** E.g. the `register_provider!` macro expects a `ProviderBuilder` impl
  that returns `Result<Arc<dyn Provider>, Error>` but the patch returns
  `Result<Box<dyn Provider>, Error>`. Fix: align the trait usage with the upstream example
  (search cachix/secretspec for `register_provider!` call sites to copy the exact return
  type).
- **Feature resolver incompatibility.** E.g. the patch adds `sops = ["dep-sops"]` to
  `[features]`, but `dep-sops` is gated on a default-features-only flag that's not
  available without `default-features = false`. Fix: set
  `dep-sops = { git = "...", default-features = false }` in `[dependencies]`.
- **Subprocess dispatch lifecycle mismatch.** The patch spawns the sops subprocess via
  `tokio::process::Command` but cachix/secretspec Provider trait expects
  synchronous `fn resolve(...) -> Result<String, Error>`. Fix: wrap subprocess in
  `tokio::runtime::Runtime::block_on` (synchronous wrapper) or refactor trait signature.

## Approach

1. From `zephyr`, `cd ~/Projects/secretspec-core && git fetch origin`.
2. `git checkout feature/sops-provider-subprocess-dispatch && git pull --ff-only`.
3. Re-apply `0001-add-sops-provider.patch` if missing
   (`git apply /etc/nixos/secretspec-fork-patches/0001-add-sops-provider.patch`).
4. `cargo check --all-features 2>&1 | tee /tmp/cargo-check.log` — capture full output.
5. If exit ≠ 0, triage by error class (missing import / type / feature / lifetime / async)
   and produce a follow-up patch `0002-fix-*.patch` with the corrections.
6. If exit = 0, run `cargo test -p secretspec --features sops` for the same exercise.
7. Add a `just secretspec-fork-cargo-check` recipe to the justfile that wraps
   `cd ~/Projects/secretspec-core && cargo check --all-features` (operator convenience).

## Risk

- First `cargo check` may pull 200+ transitive crates from crates.io; requires outbound
  network access. zephyr has it via tailscale funnel → cloudflare → egress. If pulled
  fails, check `CARGO_NET_GIT_FETCH_WITH_CLI=true` and retry.
- If the upstream cachix/secretspec main has diverged since the patch was authored, the
  patch may need regeneration. Use `git log --since="2026-07-01"` on cachix/secretspec
  to spot API changes that conflict with the patch.

## Related

- `pkgs/secretspec/default.nix` — Nix build that vendors the fork
- `pkgs/secretspec-provider-sops/default.nix` — Nix build for the sops feature
- `secretspec-fork-patches/0001-add-sops-provider.patch` — the patch series under review
- `.sops.yaml` — recipient policy that downstream decrypt paths depend on
- `just secretspec-fork-bootstrap` — clones + patch-applies the fork (Issue #9 tests this
  from clean state)
