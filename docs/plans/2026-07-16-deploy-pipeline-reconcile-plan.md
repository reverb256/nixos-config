# Plan: Deploy Pipeline Reconciliation & Drift-Defect Closure

**Date:** 2026-07-16
**Author:** Hermes (nixos-declarative-only + no-stub-delivery enforced)
**Scope:** Close every source-of-truth drift path in the NixOS/K3s deploy pipeline, harden the builder, and document the residual decisions.
**Status:** Phases 1–8 executed (deploy in flight). Phases 9–12 pending.

---

## 0. Current State (post Phases 1–8)

| Item | State |
|------|-------|
| Canonical `main` | `e0552315` (pushed to GitHub + central bare) |
| zephyr / nexus-local / central bare | all aligned to `e0552315` ✅ |
| nexus divergence (`9c7c2eb2`, 11+ commits) | **backed up** → tag `backup/nexus-divergent-9c7c2eb2` (GitHub + central) ✅ |
| zephyr WIP (freebuff re-enable + HM pin) | **backed up** → branch `backup/zephyr-wip-20260716` ✅ |
| In-flight wrong build (PID 2077642) | **killed** ✅ |
| `scripts/remote-build.sh` (zephyr path) | **fixed** — force-syncs nexus → `origin/main` before build ✅ |
| zephyr deploy (`just deploy zephyr`) | **in flight** on nexus, building healthy (verified) |

### Root cause of the whole incident
`remote-build.sh` (and the `just deploy` colmena paths) built `.#nixosConfigurations.<host>` from **nexus's LOCAL `/etc/nixos` checkout**, which had drifted (stale `origin/main` ref + local edits). The builder was treated as an equal participant in source-of-truth instead of a pure executor. Fix = builder must always reflect canonical `origin/main` before building.

---

## 1. Gap Inventory

| # | Gap | Severity | Location | Status |
|---|-----|----------|----------|--------|
| G1 | `just deploy <remote>` builds from nexus LOCAL checkout (same drift defect as the zephyr bug) | **HIGH** | `justfile:159-166` (`ssh nexus "cd /etc/nixos && nix build ..."`) | unfixed |
| G2 | `just deploy-nexus <host>` runs colmena ON nexus → evaluates nexus LOCAL hive for nexus/forge/sentry → drift | **HIGH** | `justfile:203-224`, `scripts/deploy.sh:102-109` | unfixed |
| G3 | `just deploy-nexus zephyr` / `deploy-nexus-all` footgun: zephyr node `targetHost=null` → applies zephyr config TO NEXUS | **CRITICAL** | `justfile:266-273`, `colmena.nix:54-64` | unfixed |
| G4 | No pre-deploy consistency gate: nodes' local `origin/main` can go stale silently | **MED** | missing `preflight`/sync step in non-zephyr paths | partially (zephyr path only) |
| G5 | `casdoorJwtFile` was commented out in nexus's `hosts/zephyr/services.nix`; secret presence post-deploy unverified | **MED** | `hosts/zephyr/services.nix:305` (now canonical, reverted) | verify in Phase 9 |
| G6 | Uncommitted `flake.lock` nixpkgs bump (`e7a3ca8`→`753cc8a3`) discarded without a recorded decision | **LOW** | zephyr local tree | decision logged (§4) |
| G7 | Backup artifacts (`backup/zephyr-wip-20260716` branch, `backup/nexus-divergent-9c7c2eb2` tag) need a disposition policy | **LOW** | Git remotes | documented (§5) |

---

## 2. Remediation Phases

### Phase 9 — Verify the in-flight zephyr deploy (BLOCKING, running now)
**Action (no code change):** When background build `proc_3b7b199d8d4c` completes:
1. `sudo readlink /nix/var/nix/profiles/system` → new generation > 2282.
2. `sudo nix-env -p /nix/var/nix/profiles/system --list-generations | tail -3`.
3. `systemctl list-units --state=failed` → 0 (or only known-minor).
4. `ls /run/secrets/` → all sops secrets present incl. `casdoor-hermes-jwt` (closes G5).
5. Generation label hex matches the `e0552315` build (confirm via `/nix/store/...-nixos-system-zephyr-*`).
**Acceptance:** all 5 green → zephyr deploy declared complete.

### Phase 10 — Fix G1: `just deploy <remote>` must sync builder first
**File:** `justfile` (lines 159–166)
**Change:** Replace the inline `ssh nexus "cd /etc/nixos && nix build ..."` with a sync-then-build that mirrors `remote-build.sh`:
```bash
# Before building on nexus, force nexus /etc/nixos to canonical ref
ssh nexus "bash --norc --noprofile -c 'set -e; cd /etc/nixos; git fetch origin ${REF:-origin/main}; git reset --hard ${REF:-origin/main}'"
OUT=$(ssh nexus "cd /etc/nixos && nix build --no-link --print-out-paths '.#nixosConfigurations.$host.config.system.build.toplevel'" 2>/dev/null) || { echo "Build failed for $host"; exit 1; }
```
Better: extract this into `scripts/remote-build.sh` so zephyr + remote paths share ONE sync implementation. Add a `build-on-nexus` helper invoked by both.
**Acceptance:** a `just deploy forge` build log shows `git reset --hard origin/main` on nexus before `nix build`.

### Phase 11 — Fix G2/G3: `deploy-nexus` sync + footgun guard
**File:** `justfile` (lines 198–273)
**Changes:**
1. `deploy-nexus host`: add, before the `ssh nexus "...colmena apply..."`:
   ```bash
   # Builder must reflect canonical before evaluating the hive
   ssh nexus "bash --norc --noprofile -c 'set -e; cd /etc/nixos; git fetch origin main; git reset --hard origin/main'" 2>&1 | tail -1
   ```
2. Guard the footgun — make `deploy-nexus zephyr` and `deploy-nexus-all` refuse zephyr:
   ```bash
   deploy-nexus host:
       #!/usr/bin/env bash
       set -euo pipefail
       if [ "{{host}}" = "zephyr" ] || [ "{{host}}" = "all" ]; then
         echo "ERROR: 'just deploy-nexus zephyr/all' applies to nexus (zephyr targetHost=null). Use 'just deploy zephyr'." >&2
         exit 1
       fi
       ...existing ssh nexus colmena apply...
   ```
   (Also drop the `deploy-nexus-zephyr` convenience alias or repoint it to `just deploy zephyr`.)
**Acceptance:** `just deploy-nexus zephyr` prints the error and runs no colmena; `just deploy-nexus forge` first resets nexus to `origin/main`.

### Phase 12 — Fix G4: single `preflight` sync for all paths
**File:** `scripts/preflight-check.sh` (extend) + `justfile` `preflight` recipe
**Change:** Add a check that fails the deploy if nexus's `/etc/nixos` ref ≠ `origin/main` (or auto-syncs). Make `just deploy` call `preflight` before build for every target.
**Acceptance:** a deploy attempted with a drifted nexus aborts with a clear message instead of building wrong bytes.

---

## 3. What is intentionally NOT changed (decisions)

- **Freebuff:** upstream `a2ca27fc` removed `freebuff-desktop.nix` (dead upstream URL 404). The zephyr WIP re-enabled it + pinned home-manager to `release-26.11`. Decision: **do not re-apply**; keep the WIP on `backup/zephyr-wip-20260716` for reference. If the upstream URL is revived, that's a new issue.
- **`flake.lock` nixpkgs bump:** discarded to keep the deploy deterministic on canonical lock. The bump can be re-run explicitly (`just update` → commit) if desired — not auto-applied.

---

## 4. Disposition of backups (G7)
- Tag `backup/nexus-divergent-9c7c2eb2`: **retain permanently** as the recoverable history of the divergence event. Delete only after a 30-day cooldown and explicit confirmation.
- Branch `backup/zephyr-wip-20260716`: **retain** as archival of the WIP; not merged. Garbage-collect after the next successful canonical deploy confirms no regression.

---

## 5. Verification Gate (definition of DONE)
- [ ] `e0552315` deployed to zephyr, generation bumped, 0 failed units, secrets present (Phase 9).
- [ ] `just deploy forge` build log shows nexus reset to `origin/main` before `nix build` (G1).
- [ ] `just deploy-nexus zephyr` errors out, no colmena invoked (G3).
- [ ] `just deploy-nexus forge` resets nexus to `origin/main` before colmena apply (G2).
- [ ] `preflight` blocks/stops a deploy against a drifted nexus (G4).
- [ ] A follow-up `just deploy zephyr` (after this plan) re-runs clean and produces the same store path prefix as the canonical commit (proves builder determinism).

---

## 6. Execution Order & Safety
1. Phase 9 first (current deploy must verify before any further change).
2. Phases 10–12 are **pure source edits** on zephyr (no host touched), committed + pushed, then a final `just deploy zephyr` to confirm the fixed pipeline end-to-end.
3. No `nixos-rebuild switch` on any remote during these edits except the final verification deploy.
4. All changes go through `/etc/nixos` on zephyr → commit → push → `just deploy` (declarative-only, never imperative on hosts).
