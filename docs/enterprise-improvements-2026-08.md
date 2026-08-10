# Enterprise-Grade Improvements — Proposal (2026-08-01)

Status: **Proposal + partially implemented**. Grounded in the 2026-07-31/08-01
Sentry USB-rescue recovery, the tcl-8_6/gettext nixpkgs regression, the
`distributed-builds` / `big-parallel` review, and the current repo state
(19 CI workflows, 315 modules, 27 flake inputs, 14 test files).

---

## P0 — Deployment Safety Gates

### 1. ✅ Real eval gate in CI (`nix flake check` + wired checks)
- `ci.yml` already runs `nix flake check --no-build` (quick-check job) and
  builds all 4 hosts + pushes to the nexus nix-serve cache (`cache.yml`).
- **Gap (fixed 2026-08-01):** the `tests` job ran `nix-instantiate --eval`
  on each `tests/*.nix` and **never asserted the result** — a failing test
  exited 0. Also flake.nix exported **no `checks` output**, so `nix flake
  check` never ran the 14 source-level tests.
- **Fix:** added `checks.x86_64-linux` to flake.nix that imports every
  `tests/*.nix` (except `lib.nix`) with the flake's `pkgs` and throws on
  `passed == false` / `all_pass == false`. `nix flake check` now fails on
  test regressions; CI tests job replaced with a real assertion loop.
- Acceptance: a PR that breaks firewall-lint or secrets-integrity must fail CI.

### 2. ⏳ Required branch-protection checks
- Make `parse-check`, `quick-check`, `lint`, `tests`, `security` **required**
  in GitHub branch protection for `main`. PR #336 merged with zero eval
  validation — a conflicting-unvalidated-merge footgun.
- Add `check-git-clean` to kill the `.dirty` closure class seen on Sentry
  (`…-26.11.20260610.dirty`). Tracked in #310.

### 3. ⏳ Canary deploys + post-switch health probe + auto-rollback
- `just deploy` hits all hosts simultaneously. Formalize rolling order
  (nexus → forge/sentry → zephyr) with a post-switch health check
  (sshd + key services) and rollback on failure. Colmena `--on` + a
  `switch-to-configuration test`-style verification.

### 4. ⏳ Deploy provenance / drift detection
- Record `{commit, lock-hash, closure, host}` per deploy; surface via
  `just health` / `just status`. The Sentry `.dirty` closures and
  #242's repo-vs-disk drift are exactly this gap.

---

## P1 — Flake Hygiene

### 5. ✅ /home/j_kro impurity reduction (#309, partial)
- Fixed the highest-impact host-side hardcodes (baked into every host's
  SSH config / nix machines / tmpfiles / PAM / systemd units):
  `distributed-builds.nix`, `ssh.nix`, `security-hardening.nix`,
  `home-permissions-fix.nix`.
- `opencode-image.nix` parameterized via `homeDir` argument (container image).
- Added CI `home-path-guard` job that fails on `/home/<user>` in `.nix`
  files outside `packages/` (allowlist for legit container images + the
  remaining `default =`/`example =` option values that are user-scoped
  service defaults — tracked in #309).
- Remaining: option `default = "/home/j_kro/…"` values in user-scoped
  service modules (supermemory, llamafile, voxtype, etc.) — acceptable for
  a single-user homelab; migrate to `config.users.users.j_kro.home` when
  those modules are next touched.

### 6. ⏳ Input governance with flake-checker
- Enforce: official `NixOS/…` owners, max input age, no `tarball+file`
  (was #308 — grep confirms none remain in flake.nix; close #308).
- nixpkgs updates gated by the P0 eval gate (#1) so upstream regressions
  (tcl-8_6, gettext) are caught before deploy.

### 7. ⏳ flake-parts adoption
- `flake-parts` is already an input. Modularize the 27-input outputs
  section; derive `common-modules-list.nix` from one source to kill the
  flake.nix ↔ colmena.nix sync footgun.

### 8. ⏳ Overlay cost accounting
- `overlays/bugfixes.nix` gjs/gtk4 patch forces full webkitgtk rebuilds on
  every host (observed: 37+ min on Nexus, 9464 steps). Document overlay
  cost in the module; revisit whether upstream fixed it; consider `nixpkgs`
  config overrides instead.

---

## P2 — Resilience & Recovery

### 9. ✅ Runbook captured
- `docs/sentry-usb-rescue-recovery-runbook.md` — validated end-to-end
  recovery path (export closure → gzip → ssh pipe → `nix-store --import`
  with `NIX_STORE_DIR`/`NIX_STATE_DIR` → `nixos-enter` → profile set →
  `NIXOS_INSTALL_BOOTLOADER=1 switch-to-configuration boot`).

### 10. ⏳ recover-host tooling
- Wire the runbook into `recover-host.yml` workflow + `just recover-host
  <host>` recipe. #243 (Nexus) + Sentry hit the same naive-transfer
  failures — solved pattern, encode it.

### 11. ⏳ Declarative disk layout (disko) + DR rehearsal
- Sentry's btrfs subvolume layout exists only on-disk. A declarative disko
  config (or at least the subvolume contract in-repo) + quarterly DR
  rehearsal on a spare host would cut rescue time in half.

### 12. ⏳ Preservation module (#242)
- Sentry declares zero preservation in-repo while using ephemeral
  `@root`/`@persistent` — silent drift. Standardize a preservation module.

---

## P3 — Testing Depth

### 13. ✅ tests/ wired into `checks` (with #1)
- All 14 source-level tests now run via `nix flake check`.

### 14. ⏳ One `nixos-test` VM smoke test
- Boot nexus in QEMU: sshd up, prometheus/caddy healthy,
  `systemd-analyze verify` clean. Catches activation-time failures.

---

## P4 — Architecture & Ops

### 15. ⏳ Distributed build config in-repo (already largely done)
- `distributed-builds.nix` documents the full picture (zephyr dispatcher
  max-jobs=0, nexus primary builder 12, sentry 8, forge removed 2026-07-29).
  Add a README pointer + verify `big-parallel` is exercised via nexus
  `supportedFeatures = ["big-parallel" "kvm"]`.

### 16. ⏳ Secretspec Phase 3
- Remove sops-nix dual-path; rotate the 34 `.env.secrets` placeholders.

### 17. ⏳ CI hygiene audit
- 19 workflows — audit `auto-merge-to-prod.yml` + `dependabot-auto-merge.yml`
  don't bypass P0 gates; verify all actions pinned to SHAs.

### 18. ⏳ Self-hosted Attic cache
- Replace public-cache reliance with Attic on Nexus (S3-backed via Garage).
  webkitgtk-class rebuilds become one-time costs.

---

## Top 5 to start (highest leverage / lowest effort)
1. ✅ `nix flake check` eval gate in CI + wired tests (done 2026-08-01)
2. ✅ CI `home-path-guard` (#309 partial)
3. ⏳ Make P0 jobs required in branch protection
4. ⏳ Wire tests into a `nixos-test` VM smoke test
5. ⏳ `just recover-host` + close #243/#308 with the validated runbook pattern
