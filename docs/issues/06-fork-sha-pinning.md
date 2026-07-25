# Issue #6: flake-input SHA sync — detect fork drift on rebuild

**Priority:** MEDIUM  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** Drift-cycle Stream 2c of comprehensive plan + reproducibility gap noted in
compendium item I  
**Depends on:** Issue #3 (cargo check must succeed) — verify drift detection BEFORE
pinning  
**Blocks:** rigorous reproducibility guarantee on `nixos-rebuild`

> **Context update (Phase 1a, 2026-07-25).** The original Issue #6 framing
> assumed a `src = ../Projects/secretspec-core;` style absolute-path probe,
> and proposed a `FORK_SHA = "..."` capture at the top of
> `pkgs/secretspec/default.nix` to enforce a SHA pin. Phase 1a converted the
> local fork + provider-rust into flake inputs (`flake.nix`'s `secretspec`
> and `secretspec-provider-sops` inputs), so the actual concern has shifted
> from "pin the source tree" to "detect drift between local fork HEAD and
> `flake.lock`'s resolved SHA". This issue describes the new workflow.

## Context

Phase 1a (2026-07-25) converted the local cachix/secretspec fork and the
provider-rust fork into flake inputs in `flake.nix`:

```nix
secretspec = {
  url = "git+file:///home/j_kro/Projects/secretspec-core?ref=feature/sops-provider-subprocess-dispatch";
  flake = false;
};
secretspec-provider-sops = {
  url = "git+file:///home/j_kro/Projects/secretspec/provider-rust";
  flake = false;
};
```

`flake.lock` content-addresses the resolved SHA at flake-lock time. After
update, the SHA is stable across rebuilds UNLESS someone mutates the
upstream history. The local-fork HEAD can drift (via `git pull` on the
fork, or a force-push) without `flake.lock` reflecting it if the operator
forgets to run `nix flake update`.

**There is no automated drift check.** If `~/Projects/secretspec-core` HEAD
drifts between rebuilds (e.g. someone runs `git pull` on the fork, or the
patch series is mutated on the local branch), the operator's validator
unit will rebuild silently against a different source — and the cluster
will not detect this drift.

Today this is bounded because:

- The fork is single-operator (j_kro)
- Rebuilt from zephyr, not a CI runner
- The patch series is git-tracked separately and operator-controlled

But for future reproducibility (Cluster Recovery Plan, syncthing-restored
nixos-config from `syncthing-folder-id-nixos-config`), the SHA-sync check matters.

## Acceptance Criteria

- `just secretspec-fork-sha-sync` recipe:
  - Resolves `nix flake metadata --json /etc/nixos | jq -r '.locks.nodes.secretspec.locked.rev'`
  - Reads `git -C ~/Projects/secretspec-core rev-parse HEAD`
  - Emits a `[ci] OK: secretspec-fork SHA matches flake.lock` success line OR
    a `[ci] WARN: secretspec-fork local HEAD (<hex>) != flake.lock (<hex>)`
    warning + a hint to run `nix flake update`.
- Wire the recipe into `just secretspec-validate-local` as a non-blocking
  pre-flight check. The cluster rebuild continues on drift warnings — the
  warning is informational, not blocking.
- Document the recovery path in `knowledge.md`'s Operational gotchas: a
  drift warning means `nix flake update` is needed to lock the new local
  fork HEAD into `flake.lock`.

## Optional enhancements (out-of-scope-but-nice)

A second recipe `just secretspec-fork-sha-pin` COULD be added to hard-pin
the fork SHA EXPLICITLY in `flake.nix` via `?rev=<hex>`, forcing a
`nix flake update` failure when local HEAD moves. NOT required by the
basic drift-detection acceptance criteria — implement as a fail-loud
alternative if the soft-warning approach proves insufficient.

## Approach

1. Add `just secretspec-fork-sha-sync` recipe to the justfile:

   ```just
   secretspec-fork-sha-sync:
       #!/usr/bin/env bash
       set -uo pipefail  # NOTE: no -e — drift is a warning, not an error
       cd /etc/nixos
       locked=$(nix --extra-experimental-features 'nix-command flakes' \
           flake metadata --json 2>/dev/null \
           | jq -r '.locks.nodes.secretspec.locked.rev // empty')
       local=$(git -C /home/j_kro/Projects/secretspec-core rev-parse HEAD 2>/dev/null || echo "")
       if [ -z "$locked" ] || [ -z "$local" ]; then
           echo "[ci] WARN: could not resolve secretspec-fork SHA (flake or git missing)" >&2
           exit 0
       fi
       if [ "$locked" = "$local" ]; then
           echo "[ci] OK: secretspec-fork SHA matches flake.lock ($local)"
           exit 0
       fi
       echo "[ci] WARN: secretspec-fork drift detected" >&2
       echo "       local  = $local" >&2
       echo "       locked = $locked" >&2
       echo "[ci] Hint: run 'nix flake update' to re-lock" >&2
       exit 0  # warning, not error — cluster rebuild continues
   ```

2. Wire `just secretspec-fork-sha-sync` into `just secretspec-validate-local`
   as a non-blocking pre-flight check.
3. Update `knowledge.md`'s Operational gotchas with the recovery path.
4. (Optional) Add an explicit `?rev=<hex>` pin in `flake.nix` as a
   fail-loud alternative.

## Risk

- The flake-input SHA check runs on every `secretspec-validate-local`
  invocation. If the operator intentionally wants the local fork to lead
  flake.lock (e.g. mid-development), they'll see a warning each time —
  acceptable as long as the warning is informational, not blocking.
- If the local fork checkout is missing (e.g. CI runner without access to
  `/home/j_kro/Projects/secretspec-core`), the recipe warns and continues
  rather than crashing.
- `nix flake metadata --json` requires the flake to be lock-resolvable.
  During a fresh checkout before `nix flake update`, the SHA may be empty
  — handled by the `[ -z "$locked" ]` branch.

## Related

- Issue #3 (cargo check) — must pass before SHA sync check has meaning
- Issue #9 (bootstrap recipe clean-state test) — depends on SHA-sync reproducibility
- Issue #10 (upstream PR) — when merged, SHA sync should track upstream release tag instead
- `pkgs/secretspec/default.nix`
- `pkgs/secretspec-provider-sops/default.nix`
- `flake.nix`
- `~/Projects/secretspec-core`
- `secretspec-fork-patches/0001-add-sops-provider.patch`
