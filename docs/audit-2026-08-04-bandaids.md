# Band-Aid & Workaround Audit — 2026-08-04

**Scope:** NixOS config + Home Manager + imperative `nix profile` across all 4 hosts (zephyr/nexus/forge/sentry).
**Method:** static grep sweeps (mkForce, dontCheck/doCheckByDefault, packageOverrides, useGlobalPkgs, http2, sleep, TODO/HACK comments), live `nix profile list` on reachable hosts, patch-file application tracing, prior audit cross-reference (docs/audit-2026-07-27.md).
**Status:** Findings + proper-fix design. Implementation is split into workstreams WS1–WS7 (see end); nothing in this audit was deployed.

---

## A. Imperative / non-declarative hacks (worst offenders)

### A1. `niri-hdr` is a manual cargo build + `sudo cp` into `/usr/local/bin` ⚠️ HIGH
- `hosts/zephyr/desktop.nix:27-28`:
  ```nix
  # Rebuild with: cd /tmp/niri-hdr && cargo build --release && sudo cp target/release/niri /usr/local/bin/niri-hdr
  binPath = lib.mkForce "/usr/local/bin/niri-hdr";
  ```
- The binary is built **imperatively** (outside the store) and wired into a declarative option via `mkForce`. A reboot/reinstall loses it; the closure doesn't contain it; `nixos-rebuild` cannot reproduce it.
- A declarative `pkgs/niri-hdr.nix` **already exists** and is wired into `overlays/system.nix` (`niri-hdr = prev.callPackage ../pkgs/niri-hdr.nix { inherit (prev) niri-unstable; };`) — but it carries `hash = lib.fakeHash` for **both** `smithay` and `niri` fetches, i.e. it has never been built; `pkgs/deploy-niri-hdr.sh` is the imperative deploy script for the old flow.
- **Proper fix (WS1):**
  1. Fill in real SRI hashes in `pkgs/niri-hdr.nix` (build once on nexus via `nix build` to obtain them; the fork revs are pinned).
  2. Point `programs.uwsm.waylandCompositors.niri.binPath = lib.mkForce "${pkgs.niri-hdr}/bin/niri"` (keep the `mkForce` — it intentionally beats the nixpkgs `niri-session` default — but now to a store path).
  3. Delete `pkgs/deploy-niri-hdr.sh` + any `/usr/local/bin/niri-hdr` residue; remove the `cargo build && sudo cp` comment.
- **Risk:** the fork's `postPatch` (sed of `[patch]` section + `cargoLock = null`) is fragile; the fork build may fail → verify in a scratch worktree before touching zephyr.

### A2. Imperative `nix profile` packages on every host ⚠️ HIGH
- **zephyr (~25 pkgs):** `age, age-plugin-yubikey, sops, secretspec, cargo, clippy, rustc, evil-winrm, pywinrm, pypsrp, powershell, freerdp, godot, lutris, manim, kubectl, wrangler, libvirt, openiscsi, pam_u2f, fuse, llama-cpp-python, mcp-context7, hermes-agent, freebuff-desktop-wrapper, cuda_cudart, lib(cuda libcublas), hello, home-manager-path`.
- **nexus:** `cachix, colmena, hermes-agent, pkg-config, s3fs`.
- **forge:** `hermes-agent`.
- `hello` is pure test junk. `home-manager-path` is Home Manager's own profile entry (expected). Everything else is state that:
  - is absent from the flake closure → not reproducible, not rollback-safe;
  - uses **stale pinned nixpkgs snapshots** (e.g. `cargo-1.95.0`, `kubectl-1.36.1`) that drift from the system pin;
  - cannot be audited via git.
- **Proper fix (WS2):**
  - User-level tools → `home.packages` in the HM tree (already exists for most of these — dedupe first).
  - Runtime libs (`cuda_cudart`, `libcublas`) → `environment.systemPackages` or the consuming service's env (they are already referenced by `modules/hardware/gpu-compute.nix:41` — the imperative copies are likely leftovers).
  - `colmena`/`cachix`/`hermes-agent` → systemPackages or flake apps (`.#colmena` already exists).
  - Then `nix profile remove <name>` per host and verify no consumer breaks.

---

## B. Test-suppression bandaids

### B1. Global `nixpkgs.config.doCheckByDefault = false` ⚠️ MEDIUM
- `modules/system/nix-config.nix:211`. The comment admits this nixpkgs rev does **not read** `doCheckByDefault`; the real mechanism is per-package `doCheck=false`. As written it is dead config that **masks future test signal** if a future pin starts reading it.
- **Proper fix (WS5):** remove the global flag; keep only per-package overrides.

### B2. `pythonPackagesExtensions` block — ~20 packages `dontCheck` ⚠️ MEDIUM
- `modules/system/nix-config.nix:36-121` (aiohttp, janus, segments, pytest-randomly, prometheus-client, python-socks, httplib2, google-api-python-client, google-auth-httplib2, frictionless, csvw, phonemizer, sentence-transformers) + `lix` itself (`dontCheck` + `-Denable-tests=false`).
- Self-admitted: *"Whack-a-mole until roll-forward."* The pattern used (per-package `overridePythonAttrs`) is the *correct* narrow mechanism — the debt is the breadth and the missing expiry.
- **Proper fix (WS5):** roll the nixpkgs pin forward (the comments state upstream already fixed most of these in newer commits); until then keep the overrides but: add one tracking issue with an expiry, and link each override to the upstream commit/nixpkgs PR that fixes it so they can be deleted mechanically.

### B3. `overlays/bugfixes.nix` — gjs/gtk4/webkitgtk/qtbase/libsecret `doCheck = false` ⚠️ MEDIUM
- `gjs, gtk4, webkitgtk, qtbase` disable tests with **no per-package justification**. `webkitgtk`/`gtk4` test failures are well-known *upstream* (nixpkgs already ships them with checks effectively off) — this overlay may be **redundant** with upstream, or worse, hiding a sandbox-only failure.
- **Proper fix (WS5):** verify against the pinned nixpkgs whether upstream already disables these tests; drop redundant entries; add justification + upstream ref for the rest (libsecret already has one).

### B4. `overlays/system.nix` — assimp `doCheck=false` (no comment), dufs `doCheck=false`, cups `chmod notifier` postInstall ⚠️ LOW
- `assimp` and `dufs` disable checks with no reason recorded; `cups` has a `chmod 0755 notifier` postInstall workaround with no upstream issue ref.
- **Proper fix (WS5):** add justification + upstream reference, or drop if redundant. (The dufs `nativeBuildInputs ++ [cacert]` part of the old `overlay.nix.patch` **has** landed here correctly.)

---

## C. Orphaned / stale patch files

### C1. `overlay.nix.patch` (repo root) ⚠️ MEDIUM
- Not referenced anywhere (grep across flake/git hooks/scripts/justfile = 0 hits). Its dufs fix **already landed** in `overlays/system.nix:27-31`. `overlay.nix` itself is now a shim to `overlays/default.nix`.
- **Proper fix (WS4):** delete the file.

### C2. `patches/hermes-cua-backend-linux.patch` ⚠️ MEDIUM
- Unreferenced (0 hits). `docs/issues/04-patches-directory-audit.md` already records "apply fails (upstream drift)".
- **Proper fix (WS4):** move to `docs/patches/deprecated/` (per issue #4's acceptance criteria) or delete.

### C3. `patches/openrazer-hid-report-6args.patch` ⚠️ LOW
- Unreferenced — razer is consumed via `hardware.openrazer` (nixpkgs module), not this patch.
- **Proper fix (WS4):** archive or delete; verify `hardware.openrazer` on nexus still works (patch may have been load-bearing for an older nixpkgs).

### C4. `patches/noctalia-sdr-brightness.patch` ✅ (keep, re-verify)
- Correctly wired: `modules/desktop/zephyr-sdr-brightness.nix:16` `patches = (old.patches or []) ++ [./patches/noctalia-sdr-brightness.patch]` — this is the proper `overrideAttrs` pattern.
- **Action (WS4):** re-run `git apply --check` against the pinned noctalia input per `docs/issues/04`; add the proposed `just patches-audit` recipe.

### C5. Stale comment referencing removed `niri-sdr-brightness.patch` ⚠️ LOW
- `modules/desktop/niri.nix:33` mentions `patches/niri-sdr-brightness.patch`; the patch was dropped 2026-07-25.
- **Proper fix (WS4):** clean up the comment.

---

## D. Build/cache-transport hacks

### D1. `http2 = false` duplicated in scripts ⚠️ LOW
- Declaratively set in `modules/system/distributed-builds.nix:80` (correct place, documented against `docs/zephyr-build-cache-http2-incident.md`, curl error 92).
- **Also** passed as CLI flags in `scripts/deploy/remote-build.sh:66` and `scripts/rescue/rescue-build-closure.sh:35-38` (`--option http2 false --option http-connections 16 --option connect-timeout 10 --option download-attempts 10`). Redundant: user `nix build` reads `/etc/nix/nix.conf`.
- `stash@{0}` ("preserve cache-transport residue after PR 392 merge") holds exactly this residue.
- **Proper fix (WS3):** drop the CLI flags from both scripts, keep the declarative `nix.conf` settings, drop the stash, and keep the incident doc + a tracking issue to remove `http2=false` once the underlying HTTP/2 range-transfer bug is fixed upstream.

### D2. Cache-trust weakenings ⚠️ MEDIUM (already in flight)
- `require-sigs = lib.mkForce false` (nix-config.nix:176, distributed-builds.nix:18), `accept-flake-config = true` (nix-config.nix:178), `trusted-users = [root * @wheel]` (distributed-builds.nix:19).
- **Proper fix:** already implemented as **PR #396** (unified `nix-cache-registry`, `accept-flake-config=false`, wildcard removal, assertions). `require-sigs=true` deliberately deferred until cache-signature compatibility + Sentry recovery. → Track merge of #396.

---

## E. `mkForce` inventory (157 matches — mostly legitimate)

### E1. `systemd.network.links = lib.mkForce {}` ⚠️ MEDIUM (zephyr:100, nexus:86)
- Comment: "Disable interface renaming - use actual interface names". This **nukes all** networkd link configs, including anything `modules/networking/cluster-networking.nix` / `modules/system/interface-naming.nix` contribute. `interface-naming.nix` is already DISABLED (CODE-003 legacy). A blanket `mkForce {}` is the blunt instrument for what may be a single conflicting link.
- **Proper fix (WS6):** determine the actual conflicting link; drop `mkForce {}` if nothing else sets `links`, or pin only the offending interface.

### E2. Remaining `mkForce` — legitimate per-host overrides ✅
- Host-level `mkForce false/true` for shared module defaults (sentry/nexus/forge/zephyr), `LD_LIBRARY_PATH` ROCm paths (documented), `OOMPolicy` cgroup caps (documented 2026-07-27 OOM emergency), `cluster-services` root user/group, `nvidia-wayland` powerManagement, `stylix` qt platform, sddm Relogin, sshd config hardening. These follow the documented "host-specific overrides" pattern and are **not** bandaids.

---

## F. Home-manager / config-level

- **F1.** `useGlobalPkgs = lib.mkDefault false` (modules/system/home-manager.nix:23) — intentional (documented in prior audit); keep, but centralize the decision comment. ✅ LOW
- **F2.** `modules/home-manager/zen-browser-prefs.nix:136` "Temporary workaround: Banking profile/container" — HM user prefs; review whether still needed. LOW
- **F3.** `nixpkgs.config.permittedInsecurePackages` (nodejs-20.20.2, nodejs-slim, pnpm ×2, vesktop, electron-40.10.5) — track expiry; proper fix is a newer nixpkgs or per-package override to a non-insecure version. LOW (track in WS5 roll-forward).

---

## G. Repo hygiene

- **G1.** `.crush/skills/` untracked, un-ignored — decide: commit (repo tooling) or add to `.gitignore` (local agent state). LOW
- **G2.** 10 worktrees; several stale with no origin tracking or merged PRs: `issue-380`, `issue-384`, `issue-388`, `issue-392`, `issue-sentry-lan0` (merged #391 ancestor), `issue-cache-transport` (merged PR 392 ancestor). Prune after verifying PR states. LOW
- **G3.** `docs/CODE_DEPRECATIONS.md` frozen per F-23 — recount via `rg -n 'DISABLED|TEMPORARILY' --glob '*.nix'` + `:latest` scan. LOW

---

## Workstreams (rescoped)

| WS | Priority | Scope | Contains |
|----|----------|-------|----------|
| **WS1** | P0 | zephyr desktop | A1 — finish `pkgs/niri-hdr.nix`, binPath → store path, delete deploy script + `/usr/local/bin` flow |
| **WS2** | P0 | all hosts | A2 — imperative `nix profile` → `home.packages`/`systemPackages`; remove `hello`; cleanup |
| **WS3** | P1 | build infra | D1 — drop redundant http2 CLI flags, delete stash, keep declarative setting |
| **WS4** | P1 | patches | C1–C5 — delete `overlay.nix.patch`, archive hermes-cua + openrazer, re-verify noctalia, add `just patches-audit`, fix stale comment |
| **WS5** | P1 | test suppression | B1–B4 + F3 — remove global `doCheckByDefault=false`, trim bugfixes overlay, expiry-track python block, nixpkgs roll-forward follow-up |
| **WS6** | P2 | mkForce review | E1 + spot-check remaining mkForce clusters |
| **WS7** | P2 | hygiene | G1–G3 — .crush/skills decision, worktree pruning, CODE_DEPRECATIONS recount |

**In flight (monitor, do not duplicate):** PR #394 (kubernetes parser coverage — closes the `ai-inference.nix` parse hole), PR #396 (cache trust — D2).

## Verification commands

```bash
# patch-file wiring (should only show noctalia after WS4)
rg -n 'patches/' --glob '*.nix' --glob '!*.lock' /etc/nixos/{flake.nix,modules,overlays,overlays.nix,overlay.nix.patch}
# test-suppression inventory
rg -n 'doCheck\s*=\s*false|dontCheck|doCheckByDefault|dontUsePytestCheck' --glob '*.nix' /etc/nixos
# imperative profile inventory (per host)
nix profile list
# mkForce inventory
rg -n 'mkForce' --glob '*.nix' /etc/nixos | wc -l
```
