# Workflow Hygiene Best Practices — Check Cascades, Rebase Artifacts, Branch Sprawl

**Research date:** 2026-08-18
**Primary sources:** Nix Reference Manual, Git Book, trunkbaseddevelopment.com, GitHub Docs, getsops.io
**Scope:** Solutions to the failure patterns observed in the 2026-08-18 branch/PR cleanup session.

## Executive summary

The session surfaced four recurring failure classes:

1. **Check cascade masking** — `just check` aborted at the *first* failing check, hiding six independent regressions (including a live sentry firewall drop) behind one visible error.
2. **Rebase artifacts** — rebases silently dropped or duplicated config lines (`sentry/firewall.nix` import, duplicate forge `ageKeyFile`) with no conflict marker.
3. **Parallel-session merge friction** — main moved repeatedly mid-session, producing corrupted rebases and five "absorbed by main" branches.
4. **Branch sprawl** — stale branches/worktrees accumulated across three checkouts, and a remote-branch deletion silently failed on GitHub.

Each has a documented, primary-source-backed practice. This document covers the fixes and the repo-specific gaps.

---

## 1. Check cascade masking — report all failures, not the first

### The problem

`nix flake check` stops at the first error by default. The repo's `mkCheck` helper (flake.nix:359-366) makes this worse: it builds each check as a derivation and `throw`s on failure, so the *first* failing check in evaluation order aborts the whole run. Everything after it is masked. In this session, fixing firewall-lint surfaced flake-input-consistency, then host-configuration (sentry firewall drop), then k8s-manifest-validation (media-arr `:latest`), then options-consistency, then zephyr-dispatcher-policy, then a forge eval error — six hidden failures.

### Best practice (primary sources)

- **Nix Reference Manual (`nix flake check`):** "If the keep-going option is set to true, Nix will keep evaluating as much as it can and report the errors as it encounters them. Otherwise it will stop at the first error."
- The NixOS/nix issue tracker (issue #4450, "`nix flake check` should not stop on first error") documents the fail-fast behavior as a known limitation.

### Repo-specific fixes

1. **Change `mkCheck` to aggregate, not throw.** Instead of `throw "test ${name} FAILED: ..."` per check, produce a single derivation that fails with a *combined* report of every failing check (the tests already return `failures` and `passed`). With `--keep-going` this turns one red run into a complete failure report.
2. **Add `--keep-going` to the `check` recipe in the justfile** (`nix flake check --option pure-eval false --keep-going`). Nix will evaluate as much as it can and report each error as encountered.
3. **Keep the per-check design (one derivation per test)** — it gives good granularity for CI status reporting. Only the aggregation/throw behavior needs changing.

---

## 2. Rebase artifacts — silent content loss with no conflict

### The problem

Two regressions were caused by rebases that dropped or duplicated lines *without* producing a conflict:

- sentry's `configuration.nix` lost its `./firewall.nix` import (rebase artifact in `3a2e43959`, an unrelated justfile commit) — source-restricted firewall rules went dead silently.
- forge's `services.secretspec-creds` got a duplicate `ageKeyFile` (`7d59e76a5` added the corrected path without removing the old one) — eval broke.

These are the most dangerous rebase failures: no conflict markers, no error, just wrong output.

### Best practice (primary sources)

- **Git Book, "Rerere" (Git-Tools-Rerere):** enable `git config --global rerere.enabled true`. "If you do this continuously, then the final merge should be easy because rerere can just do everything for you automatically." This is specifically for keeping long-lived topic branches rebased without re-resolving the same conflicts — and `Recorded preimage for ...` lines (visible in this session's rebase logs) are the signal it is active.
- **Trunk Based Development (trunkbaseddevelopment.com/short-lived-feature-branches):** "the branch should only last a couple of days. Any longer than two days, and there is a risk of the branch becoming a long-lived feature branch." Short branches dramatically shrink the window for rebase-artifact drift.
- **Structural/architecture tests** (industry pattern: ArchUnit for JVM, PyTestArch for Python, NetArchTest for .NET): encode wiring invariants as tests so a dropped import fails CI. The repo already does this well — `tests/host-configuration.nix` (`allFirewallsImported`) is exactly the right pattern and is what eventually caught the sentry regression.

### Repo-specific fixes

1. **Enable `rerere.enabled true` globally** (and on the deploy host) — the exact scenario in this session (repeated rebases of the same branches onto moving main) is what rerere is for.
2. **Extend the import-integrity test class.** `host-configuration.nix` already checks firewalls are imported; add the same guard for any file whose import is load-bearing (secretspec wiring, k3s, caddy routes). One assertion per host per critical import.
3. **Add a duplicate-attribute guard to the check suite.** The forge `ageKeyFile` failure was an eval error; a static scan for repeated attribute names inside the same attrset block would catch the class earlier. (Lower priority — eval already catches it; the masking fix in §1 makes eval errors visible in aggregate.)

---

## 3. Parallel-session merge friction — serialize integration

### The problem

Multiple sessions advanced main during the cleanup: three separate catches were needed, one mid-rebase kill corrupted a worktree (1585-file mess, stale `index.lock`), and five branches turned out fully absorbed by main. This is the classic high-churn trunk problem.

### Best practice (primary sources)

- **GitHub Docs, "Managing a merge queue":** "A merge queue helps increase velocity by automating pull request merges into a busy branch and ensuring the branch is never broken by incompatible changes." The queue applies each PR to the latest target branch *and* other queued PRs before running required checks — precisely the "main moved under me" failure mode. Requires a `merge_group` event in CI workflows.
- **GitHub Docs, "About protected branches":** require status checks, require linear history, dismiss stale approvals. "If you enable required reviews... the approving review is dismissed as stale" when the diff changes — the mechanism that forces re-validation after integration.
- **GitHub Docs, "Managing the automatic deletion of branches":** enable *Automatically delete head branches* so merged PR branches never linger.

### Repo-specific fixes

1. **Enable "Automatically delete head branches"** in repo Settings → Pull Requests. This session's remote branches survived merges because `gh pr merge --delete-branch` aborted on local worktree lock errors; the setting is the durable fix.
2. **Consider a merge queue for `main`** (organization-only feature). With CI workflows adding the `merge_group` trigger, queued PRs get validated against the latest main + each other. This is the highest-leverage fix for the parallel-session churn.
3. **At minimum, add branch protection**: require status checks (`just check` equivalent), require linear history (squash merge already used), dismiss stale reviews on update. This forces each PR to be validated against current main before merge.
4. **Recover from killed rebases the documented way** (used successfully this session): clear the stale `index.lock`, `git reset --hard HEAD` to restore the branch ref, then re-run the rebase fresh — rather than attempting `--abort` against a corrupted index.

---

## 4. Branch sprawl — lifecycle enforcement

### The problem

~30 branches/worktrees across three checkouts, including a broken `central` remote URL, root-owned `.git` files, stale `/tmp` worktrees, and a missing bare repo on the server. Five of fifteen PRs were closed as "already absorbed by main" — work that had effectively died on the vine.

### Best practice (primary sources)

- **trunkbaseddevelopment.com:** branch lifetime should be "a couple of days"; merge to trunk frequently; delete the branch on merge. "If you merged the part-complete short-lived feature branches to anywhere else, then you have broken the contract of trunk-based development."
- **GitHub Docs:** automatic head-branch deletion (§3 above).
- **Git Book, `git worktree`:** remove worktrees when done (`git worktree remove`); `git worktree prune` cleans stale metadata for worktrees deleted behind git's back (the `/tmp/z-*` cases this session).

### Repo-specific fixes

1. **Adopt a "merge fast" rule for issue branches:** same-day or next-day merge for fixes; no branch older than ~2-3 days without an explicit decision. The five absorbed branches all exceeded this and cost the session's rebase effort.
2. **Add a stale-branch sweep to the CI suite or a scheduled job:** flag `origin/*` branches with no commits in N days and no open PR. (The repo's `stale.yml` workflow exists for issues/PRs; extend to close stale PRs.)
3. **`git worktree prune` as part of the cleanup recipe** (`just rm-worktree` already exists; add `prune` to `just` hygiene target).
4. **Central-bare-repo hygiene:** the hm-config central bare repo did not exist on the server (`/srv/git/` had only `nixos-config.git`); it was created this session. Document the mirror setup so it is re-creatable (see `docs/reference/cluster-architecture.md` for the mirror topology).

---

## 5. SOPS key rotation — order matters

### The problem

The a6-validator rebase conflicted on a sops-encrypted file whose recipient list had been rotated on main. The branch's pre-rotation recipient was deliberately superseded by the 08-16 age-identity rotation; merging the branch's version would have re-added a revoked key.

### Best practice (primary sources)

- **getsops.io, "Key management":** use `sops updatekeys` (driven by `.sops.yaml`) for adding/removing keys without rotating the data key; use `sops rotate -i` to generate a new data key and re-encrypt values.
- **Compromised-key order (getsops.io):** (1) remove the key from `.sops.yaml`, (2) `sops updatekeys secret.sops.yaml`, (3) `sops rotate --in-place secret.sops.yaml`, (4) commit. "If done in the wrong order, the compromised key could still have access to the data in some cases."
- **When removing keys, rotate the data key** (`-r`): "otherwise, owners of the removed key may have had access to the data key in the past."

### Repo-specific fixes

1. **Never hand-merge sops `enc:` blobs.** Ciphertext conflicts are unresolvable by hand (MAC covers the whole file). The correct resolution is recipient-set comparison + re-encryption via `sops updatekeys`/`sops rotate`, as done for #676 (main's rotated recipient set kept, byte-identical).
2. **Treat the 08-16 rotation as the standing rule:** any branch touching `secrets/` must rebase onto current main first; the `updatekeys` result on main wins over any pre-rotation branch content.
3. **Add a check for revoked/rotated recipients** if the repo grows beyond the current key set (the sops `--decrypt --output` validation in the CI suite can assert the recipient list matches `.sops.yaml`).

---

## 6. Supply chain — pinning (already fixed)

The media-arr `:latest` violation (7 linuxserver images) was fixed in this session by pinning to concrete tags, each verified by digest against `latest`. This matches the repo's existing supply-chain rules (no `:latest` tags, admission policy). Keep the `k8s-manifest-validation` check (`noHardcodedImageTags`) as the regression guard — it is what caught this class.

---

## Priority order

| Priority | Fix | Effort |
|---|---|---|
| 1 | `mkCheck` aggregation + `--keep-going` in `just check` | Small (one derivation) |
| 2 | GitHub: enable *Automatically delete head branches* | One click |
| 3 | GitHub: branch protection on `main` (required checks, linear history, stale-review dismissal) | Medium (config) |
| 4 | `git config rerere.enabled true` on all dev hosts + `/etc/nixos` | One line |
| 5 | "Merge fast" rule: no issue branch > 2-3 days without a decision | Process |
| 6 | Merge queue for `main` (+ `merge_group` CI triggers) | Larger (org feature + CI) |
| 7 | Extend import-integrity tests to all load-bearing imports | Small |
| 8 | `git worktree prune` in the hygiene recipe | One line |

## Sources

- Nix Reference Manual — `nix flake check` (`--keep-going`): https://nix.dev/manual/nix/2.18/command-ref/new-cli/nix3-flake-check
- NixOS/nix issue #4450 (fail-fast limitation): https://github.com/NixOS/nix/issues/4450
- Git Book — Rerere: https://git-scm.com/book/en/v2/Git-Tools-Rerere
- Trunk Based Development — Short-lived feature branches: https://trunkbaseddevelopment.com/short-lived-feature-branches/
- GitHub Docs — About protected branches: https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches
- GitHub Docs — Managing a merge queue: https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue
- GitHub Docs — Managing the automatic deletion of branches: https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-the-automatic-deletion-of-branches
- getsops.io — Key management (updatekeys / rotate / compromised-key order): https://getsops.io/docs/usage/key-management/
