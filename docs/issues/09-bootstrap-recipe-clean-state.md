# Issue #9: bootstrap recipe + secretspec-fork-bootstrap clean-state test

**Priority:** MEDIUM  \n**Status:** Open  \n**Created:** 2026-07-25  \n**Origin:** Drift-cycle compendium item C2 + Stream 7-adjacent  \n**Depends on:** Issue #3 cargo check (if the bootstrap recipe must apply patches that
need to build, they must compile first — but the bootstrap test only verifies
clone+patch+branch-exists, not building)  \n**Blocks:** Cluster Recovery Plan (syncthing-restored /etc/nixos must be able to clone
the fork and patch it from scratch)

## Context

`just secretspec-fork-bootstrap` is a recipe in `justfile` that clones
`https://github.com/cachix/secretspec` to `~/Projects/secretspec-core` on the
`feature/sops-provider-subprocess-dispatch` branch + applies
`/etc/nixos/secretspec-fork-patches/0001-add-sops-provider.patch`. The recipe exists but
**has never been tested from clean state** — the working fork checkout today was set up
manually months ago; we have no proof that a fresh clone + patch application succeeds.

For Cluster Recovery Plan compliance (`CLUSTER_RECOVERY_PLAN.md` and the syncthing
`folder-id-nixos-config`), the operator must be able to recreate the fork on a fresh
host. If the recipe is silently broken, the recovery is one operator-skill deeper than
expected.

## Acceptance Criteria

- `rm -rf ~/Projects/secretspec-core && just secretspec-fork-bootstrap` from a clean shell
  completes within ~30 seconds (git clone + patch apply).
- After bootstrap, `cd ~/Projects/secretspec-core && git log -1 --format='%h %s'` shows the
  expected branch HEAD + a commit message mentioning the sops-feature work.
- After bootstrap, `cd ~/Projects/secretspec-core && git apply --check /etc/nixos/secretspec-fork-patches/0001-add-sops-provider.patch`
  exits 0 (the patch is either already applied OR cleanly re-applies as no-op).
- `cd ~/Projects/secretspec-core && cargo check --features sops` exits 0 (subject to
  Issue #3 being green — out of scope for THIS issue).

## Approach

1. From zephyr, `rm -rf ~/Projects/secretspec-core` after backing up current state if
   desired (`cp -a proj secretspec-core.bak`).
2. Run `just secretspec-fork-bootstrap` from the cluster root.
3. Verify outcomes:
   - `cd ~/Projects/secretspec-core && git remote -v` shows the cachix origin.
   - `cd ~/Projects/secretspec-core && git branch --show-current` shows
     `feature/sops-provider-subprocess-dispatch`.
   - `cd ~/Projects/secretspec-core && git log -1 --format='%h %s %d'` — capture and
     report.
   - `cd ~/Projects/secretspec-core && git apply --check /etc/nixos/secretspec-fork-patches/0001-add-sops-provider.patch`
     should exit 0 (means patch is already applied, no-op for fresh state).
4. If any command fails, capture output and choose: adjust bootstrap recipe to use
   `git am <patch>` instead of `git apply <patch>`, or fix patch metadata.
5. After clean-state verification, optionally `mv secretspec-core.bak ~/Projects/secretspec-core`
   to restore operator workflow (or keep the bootstrap-state since cargo check is next).

## Risk

- `git clone` of a GitHub repo requires network egress. Already available on zephyr via
  tailscale-funnel.
- If the patch has been mutated since the recipe was authored, `git apply` will fail; need
  to either rebase the patch or switch to `git am`.
- If GitHub branch is force-pushed between bootstrap tests, the SHA changes but the
  recipe still works (cloning is ref-based, not SHA-pinned).

## Related

- `justfile` (`secretspec-fork-bootstrap` recipe — target)
- `~/Projects/secretspec-core` (the local fork checkout being recreated)
- `secretspec-fork-patches/0001-add-sops-provider.patch` (the patch series being
  re-applied)
- `pkgs/secretspec/default.nix` — references the fork path
- `pkgs/secretspec-provider-sops/default.nix` — references the fork path
- Issue #3 (cargo check dependency)
- Issue #6 (SHA pinning — bootstrap should print the SHA for traceability)
- Issue #10 (upstream PR — bootstrap recipe may evolve when fork is merged + tagged)
- `CLUSTER_RECOVERY_PLAN.md` — recovery-path dependency
