# Build Settings & Session Recommendations (2026-08-03)

**Purpose:** Consolidated recommendations from the 2026-08-03 zephyr OOM-deploy incident — build-settings configuration for all 4 hosts, Lix version status, and follow-up actions.
**Audience:** Cluster operators, CI maintainers
**Last Updated:** 2026-08-03
**Status:** ⚠️ Partially applied (config committed; nexus rebuild + post-deploy verification pending)

---

## 1. Lix version status

| Host | Installed | Notes |
|------|-----------|-------|
| zephyr | Lix 2.95.2 | Also advertises x86_64-v1/v2/v3 as additional system types |
| nexus | Lix 2.95.2 | Builder host — needs rebuild to pick up new config |
| forge | Lix 2.95.2 | Miner host |
| sentry | unreachable | Still in USB rescue; host key rotated |

- **Upstream latest: 2.95.3** (one patch release behind; 2.95.x is current stable line).
- nixpkgs is pinned at `0954f7ee...` (2026-07-29); its default `lix` attr is 2.94.2, but the overlay pins `lixPackageSets.lix_2_95` → 2.95.2.
- **Upgrade path:** trivial — bump `lix_2_95` to `lix_2_95` at 2.95.3 via the next `nixpkgs` bump, or add a `lix_2_96` package set when it exists. No urgency; 2.95.2 → 2.95.3 is a patch (test-fix) release.
- **Lix-specific notes discovered:**
  - `max-jobs × NIX_BUILD_CORES` = max parallel processes (Lix's own tuning doc). 16×16=256 was "very likely oversold" → nexus OOM at 15:53.
  - Lix never runs two builds under the same nixbld UID — max-jobs is also bounded by nixbld UID count.
  - Lix sandbox is for **reproducibility**, not security isolation.
  - `accept-flake-config = true` is explicitly warned against when trusted users exist (any flake can inject nixConfig). Currently `true` live on nexus.
  - `require-sigs = false` is live on nexus (insecure). Git config sets `mkForce false` — recommend revisiting.

## 2. Build-settings configuration (per host)

### Current effective settings

| Setting | zephyr | nexus | forge | sentry |
|---------|--------|-------|-------|--------|
| role | dispatcher (never builds) | primary builder | miner (never builds) | builder (down) |
| max-jobs (git) | 0 | 12 | 4 | 8 |
| cores (git) | 2 | 12 | 6 | 8 |
| max-jobs (live nix.conf) | — | **16 ⚠️ drifted** | — | — |
| cores (live nix.conf) | — | **16 ⚠️ drifted** | — | — |
| sandbox | true | true | true | true |
| builders list | — | nexus, zephyr (in machines) | removed 2026-07-29 | removed 2026-08-03 |
| binary cache host | serves :50000 | consumes | consumes | consumes |

### Recommendations

1. **nexus: fix the live nix.conf drift (P0).** Live `max-jobs=16 cores=16` vs git `12/12`. This caused the 15:53 OOM (16×16=256 oversold). The nexus rebuild (pending) regenerates nix.conf from git → 12/12. Verify after rebuild: `nix show-config | grep -E 'max-jobs|cores'`.
2. **nexus: keep sandbox=true (DONE, e072faab).** Required — Flutter/AOT (localsend) RPATH bug.
3. **nexus: consider MemoryHigh=32G + MemoryMax=36G on build units.** systemd manpage: MemoryHigh is the primary control, MemoryMax the last line of defense. Currently only MemoryMax=36G set on the ad-hoc build unit. The remote-build.sh path (`systemd-run --user`) should be hardened to include both.
4. **Build farm:** forge (miner) and sentry (auth broken / rescue) removed from `machines` (ed5a5b5a, d32394f8). Re-add sentry after recovery with maxJobs=8, speedFactor=6, protocol=ssh.
5. **trusted-substituters drift:** live nexus has empty `trusted-substituters` → the 6 cachix keys in git are dead until nexus rebuild. Post-deploy: verify `nix show-config | grep substituters` shows all 7.
6. **require-sigs / accept-flake-config:** revisit after rebuild. `require-sigs=false` is deliberate for the internal zephyr-cache (:50000 unsigned) but insecure. Consider `accept-flake-config = ask` per Lix guidance.
7. **zephyr:** keep max-jobs=0 forever (31GB RAM — the 2026-07-27 OOM incident root cause was a local `nix build` falling back to 2 local jobs).
8. **max-silent-time:** live nexus has 14400 (4h) vs git 3600 — harmless but loose; converges on rebuild.

## 3. Session recommendations (culminated)

### A. OOM defense on zephyr (DONE — eebc57ca, pushed)
- earlyoom `--avoid` += `steam|GameThread|REDprelauncher` (was missing — steam/games were kill candidates).
- noctalia.service `ManagedOOMSwap = "off"` — oomd can no longer target the gaming session (completes the 2026-07-27 hardening).
- zram `memoryPercent 40 → 50` (~15.6G headroom vs 12.5G that hit 100%).
- oomd-fleet.nix `SwapUsedPercent=85` percent-key fix — was committed 2026-07-27 but **never deployed** (zephyr was on a Jul-26 generation). The deploy being built now includes it.

### B. Deploy/build resilience (operational findings — codify in scripts)
1. **Never launch builds via `systemd-run --user` on a host running user-session services.** The 09:54 crash: GitHub Actions runner OOM'd inside the user session → killed `user@1000.service` → killed the build. Root systemd unit (`systemd-run --unit=... --scope` via sudo, or system-level) is immune.
2. **Sandbox must be a daemon-side setting** — client `--option sandbox true` does NOT propagate to remote builders via ssh-ng. Enforced in config (e072faab).
3. **Memory-bound heavy builds:** `--max-jobs 4 --cores 4` + MemoryMax kept nexus (46G) under OOM. Documented in Lix's tuning page.
4. **Builds resume from the store** — nix-copy-closure / already-built derivations are cached; restarts don't redo everything.

### C. Repository hygiene fixes that landed
- niri-config.nix syntax error on origin/main (2a35e1c8) — **fixed & pushed** (9581dc52, sibling agent's local commits). Verify all 4 hosts eval before any deploy.
- Local eval can be masked by a dirty worktree — the eval "passed" locally because uncommitted fixes were present. **Always eval origin/main, not the working tree**, or use a clean worktree.

### D. Post-deploy verification checklist (zephyr)
```bash
systemctl cat earlyoom | grep ExecStart          # avoid list has steam|GameThread|REDprelauncher
systemctl --user cat noctalia | grep ManagedOOM  # ManagedOOMSwap=off
zramctl                                            # ~15.6G
cat /run/current-system/etc/systemd/oomd.conf     # SwapUsedPercent=85
```

## 4. Open GitHub issues to update
- **#388** (niri-config syntax) — fixed by 9581dc52; close after verifying.
- **#387 / PR #391** (VR Proton-GE-RTSP) — ready for review.
- **#380** (caddy bump) — still open.
- **#377/#376/#375/#374/#373/#372** (sentry recovery) — sentry still in USB rescue; acceptance gate pending.
- **#341** (canary/rolling deploys) — recommend implementing; this session's 5 build failures all stemmed from unguarded single-host deploys.
- **#342** (deploy provenance) — recommend; drift detection would have caught the max-jobs 16-vs-12 and the never-deployed oomd-fleet change.
- **#344** (P0 CI gate) — recommend; the niri syntax error shipped because CI has no real eval gate.

---

**Recent Changes**
- 2026-08-03: Initial version.
