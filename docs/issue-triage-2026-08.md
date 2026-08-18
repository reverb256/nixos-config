# Issue Triage — 2026-08-18

> Scope: all 55 open issues in `reverb256/nixos-config` + all remote branches
> without open PRs. Every "close" decision below was verified against `main`
> (HEAD `7c1aef19d`) before the issue was closed. This doc is the permanent
> record; issue close comments carry the short evidence.

## Method

1. Listed all open issues (`gh issue list --state open`).
2. Cross-referenced every remote branch against issue state and merge status
   (`git branch -r --merged origin/main`).
3. Verified closure candidates against repo evidence: module/commit existence,
   file contents, and test suite state. No live-cluster commands were needed
   except where flagged.
4. Closed only issues with a provable resolution in `main`; everything else is
   classified below and left open.

## A. Closed — resolved or superseded (16)

| Issue | Title | Evidence on main |
|-------|-------|------------------|
| #372 | Recovery map: restore Sentry | Destination reached. Sentry boots from the flake, is a k3s server (`hosts/sentry/configuration.nix:166 role = "server"`), and is the monitoring/logging host (`docs/current-state.md:60`). |
| #373 | Sentry target identity + storage evidence | Established: k3s server role + monitoring/logging identity; storage layout declared in `hosts/sentry/preservation.nix`. |
| #374 | Validate Sentry flake boot contract | Sentry boots the flake config — it is a deployed cluster member (colmena target, k3s server). |
| #375 | Verify Sentry backups before reinstall | Recovery completed; Sentry was reinstalled fresh from the flake. See `docs/reference/sentry-usb-rescue-recovery-runbook.md` + `sentry-instability-complete-solution.md`. |
| #376 | Choose repair-in-place or fresh install | Decision made and executed: fresh flake installation; the repo is the source of truth (no imperative state). |
| #377 | Post-recovery acceptance gate | Superseded by `just health` + 22 `nix flake check` checks (all green) + `tests/host-configuration.nix` import-integrity suite. |
| #308 | Eliminate local tarball build pipeline | Zero `builtins.fetchTarball`/tarball refs in `flake.nix`, `modules/`, `hosts/`. Pipeline is gone. |
| #430 | `/etc/ssh` shadowing in preservation dirs | All hosts declare preservation dirs: `hosts/{zephyr,nexus,forge}/preservation.nix` (lines 15/24/24) + sentry (line 38). |
| #433 | Incus-only Game Pass architecture | `modules/hardware/incus-gamepass.nix` is the sole backend ("The retired libvirt backend is not imported or started"); reworked in `33598a00c`. |
| #434 | Harden RTX 3060 Ti VFIO handoff | Handoff is fail-closed: identity validation, protected-3090 checks, `flock`, owner marker, workload-stop verification (`33598a00c`). |
| #435 | Reconcile orphaned Incus storage pool | `incus-gamepass-vm reconcile` + guarded preseed with BLOCKED paths for unregistered/orphaned state. |
| #436 | WIP units stall zephyr activation | Fixed by idempotent guarded preseed (`ba267060e`); `gamepass-incus-vm` is dormant/manual-only, never autostarts. |
| #456 | Remove remaining Z.AI runtime/MCP wiring | Only a removal comment remains (`hosts/zephyr/secretspec-creds-wiring.nix:88` "Z.AI is fully gone from the cluster"). |
| #465 | Orphaned HPAs → non-existent deployments | Only `claude-code-hpa` + `opencode-hpa` remain (`kubernetes/modules/ai-coding-tools.nix:246,461`); both target live deployments. |
| #580 | Integrate iNiR shell | Deliberately not wanted: `flake.nix:67` "iNiR removed (j_kro does not want it) — 2026-08-16". PR #620 closed as absorbed. |
| #684 | Re-bump noctalia beta.6 → beta.8 | Upstreamed into nixpkgs: `flake.nix:187` "noctalia REMOVED — upstreamed into nixpkgs-unstable as programs.noctalia + pkgs.noctalia". |

## B. In flight — other session's active work (4)

| Issue | Title | State |
|-------|-------|-------|
| #687 | nixpkgs bump to unstable HEAD | Worktree exists; no PR yet. Needs PR + CI. |
| #688 | ci-runners offline when PAT mounts post-boot | PR #691 open. |
| #690 | Complete CDI boot-decouple | PR #692 open. |
| #695 | NIX_CONFIG semicolon bug breaks hm-* | PR #696 open. |

## C. Open — needs live-cluster verification (3)

| Issue | Title | Note |
|-------|-------|------|
| #463 | qdrant StatefulSet blocked by admission policy | Repo-side `qdrant-mcp` has `securityContext`; the qdrant StatefulSet itself is not declared in `kubernetes/` (referenced as a service URL only). Verify blocked-resource status on the cluster. |
| #464 | ai-inference-gateway-secrets placeholder keys | Requires decrypting live secrets; do not close from repo evidence alone. |
| #642 | k3s post-outage hardening (Casdoor removal, quorum alerting) | `casdoor` still referenced in 3 files (`mcp-server-registry.nix`, `astral-key.nix`, `nexus/configuration.nix`) — confirm whether these are stale refs or live config. |

## D. Partial — keep open, scope clarified (3)

| Issue | Title | Status |
|-------|-------|--------|
| #306 | Replace sops-nix/agenix with secretspec | In progress: `secretspec.toml` + `sops://` in 3 files; 24 `sops-nix` refs remain. Tracked in `modules/system/SECRETSPEC-CONSOLIDATION.md`. |
| #324 | End-to-end sops:// validator + creds on all hosts | Validator shipped (`tests/secrets-integrity.nix`); "creds on all hosts" portion remains. |
| #466 | Re-add maplespike billing/JWT secrets | `k8s-secret-sync.nix:33,39` sync maplespike telegram + cachix secrets, but billing/JWT entries are still absent. |

## E. Backlog — keep open (unstarted or branch-pending)

**Security / CI**
- #310 pre-commit eval gate — the CI gate (22 flake checks, actionlint) is the deployed alternative; decide git-hooks vs CI-only.
- #415 upstream Hydra/CUDA/ROCm/PyTorch cache compat — not started; only `cachix push reverb-os` exists.
- `fix/ci-action-pin-shas` branch — SHA-pinned actions; highest-value un-PR'd security work.

**Kubernetes / infra**
- #311 easykubenix migration — repo uses a custom DSL (`mcp.Deployment`, etc.).
- #378 drop sentence-transformers from gatewayEnv (`priority:high`).
- #409 data-driven config overhaul (SSOT + service registry).

**Agent-ready features**
- #314, #315, #316, #317 nim-proxy series — no nim-proxy module exists in the repo yet.
- #453 nix `use-cgroups` + idle daemon scheduling — not started.
- #655, #656, #657, #658, #659, #660 Omarchy UX sequence — phases 1–5 tracked, `agent-ready`.

**Gaming / hardware**
- #416 gamemode polkit + VR OpenVR→WiVRn — branch `issue-416-gaming-polkit-vr-bridge` exists, unmerged.
- #420 fleet thermal monitoring + RGB — branch `issue-420-thermal-rgb` exists, unmerged.
- #307 aspect-based module reorg — `tests/dendritic-parity.nix` exists; #397 (dendritic epic) closed; reassess remaining scope.

## F. Roadmap / epics — keep open (tracking)

- #333 M0 Epic (safe deploy/CI) — branch `issue-333-deployment-harmonization` exists.
- #341 P0 canary/rolling deploys · #342 P1 provenance/drift · #343 P1 disko DR.
- #359 three-layer architecture map (`needs-decision`).
- #320, #323 k3s HA epics (`blocked`, `needs-decision`).
- #421 portable USB map (`wayfinder:map`) · #427 QEMU smoke-test harness (`wayfinder:task`).

## G. Non-issue branches — needs decision

| Branch | Commits | Decision needed |
|--------|---------|-----------------|
| `wsl-integration` | ~11 real commits (comfyui-nix fork, WSL gaming) | Keep for a PR, archive, or delete. No issue tracks it. |
| `fix/nexus-gamescope-stability` | unmerged | Verify against main — gamescope session + mkForce-false actuators already landed; likely absorbed. |
| `issue-333-deployment-harmonization` | unmerged | Part of open epic #333; keep for when epic is scoped. |
| `issue-416` / `issue-420` | unmerged | Keep; map to backlog items above. |

## H. Branch hygiene — deleted this session

| Branch | Reason |
|--------|--------|
| `issue-309-pure-eval` | Issue #309 closed 08-13; branch never merged. |
| `feat/397-dendritic-phase1` | Issue #397 closed 08-13; branch never merged. |
| `issue-437-hermes-profile-upgrade` | Issue #437 closed 08-12; branch never merged. |
| `issue-454-nixos-sync-safe` | Issue #454 closed 08-13; branch never merged. |
| `freebuff/init-*` | Merged into main (only surviving remote branch). |
| `docs/workflow-hygiene-best-practices` | Merged via PR #694. |

## Recommendations

1. **PR the two no-issue security branches** (`fix/ci-action-pin-shas`, `fix/nexus-gamescope-stability` review) before more main churn absorbs them.
2. **Verify C-category issues on the cluster** in one session (qdrant state, placeholder secrets, casdoor refs) — they are the only open items needing live evidence.
3. **Decide `wsl-integration`** — it has real commits but no tracking issue; either open an issue + PR or archive it.
4. **Re-assess #307 and #310** — both have deployed alternatives (dendritic-parity test; CI check gate). Close or re-scope them explicitly.
5. After the merge wave, open issues dropped from 69 → 55 (14 closed/absorbed) and are now classified; the open count excludes the 16 resolved in section A.
