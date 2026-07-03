# Plan: NixOS Configuration Audit Remediation

**Created:** 2026-07-03 | **Last Verified:** 2026-07-03
**Cluster branch:** `main` ahead of `origin/main` by 1 commit
**Repo size:** 367 `.nix` files, 57,337 lines

## Goal

Address every finding from the comprehensive audit (alejandra + statix + deadnix + DRY + flake dep map) through 11 reviewable PRs sequenced so each PR keeps `just check` green and SSH safe. Eliminate latent bugs, reduce technical debt, and establish structural helpers to prevent new debt accumulation.

---

## Audit Findings (Source of Truth)

### `alejandra --check .`

- **105 of 369 files** require reformatting (28%)
- **2 files have syntax errors blocking the formatter:**
  - `kubernetes/modules/ai-inference.nix` — error at line 163:6 ("expecting end of file")
  - `hosts/nexus/supermemory.nix` — error at line 3:13 ("expecting end of file")

### `statix check .`

- **Repeated-keys warnings (~15 files, latent overwrite bugs):**
  - `modules/system/cluster-firewall.nix:25,40`
  - `modules/common-host-defaults.nix:72,82`
  - `kubernetes/modules/host-services.nix:70,541`
  - `hosts/usb/configuration.nix:205,269,283`
  - `kubernetes/modules/mcp-servers.nix:30`
  - `modules/home-manager/common.nix:19,22`
  - `modules/system/home-manager.nix:83`
  - `modules/services/syncthing.nix:79`
  - `kubernetes/modules/tailscale.nix:78`
  - `hosts/nexus/hardware.nix:6`
- **Useless let-in:** 1 instance (`kubernetes/modules/gpu-tuning.nix`)
- **Assignment instead of inherit:** 1 (`tests/options-consistency.nix:2`)

### `deadnix -f`

- Hundreds of unused `{ pkgs }` / `{ config }` / `{ lib }` lambda arguments across `modules/home-manager/`, `modules/services/`, `kubernetes/modules/`, `modules/system/`
- Specific dead let bindings to remove: `set-evdev-deadzone` (modules/gaming/gaming.nix:10), `color0`/`color7` (modules/home-manager/btop.nix), `serviceCIDR`/`kubeFlannelGateway` (modules/network/cluster-dns.nix), `tomlModels` (modules/ai-models.nix), `cluster` (modules/service-registry.nix), `nixCsiDrv`/`scratchImage` (kubernetes/modules/miners-csi.nix), `profitSwitcherScript` (kubernetes/modules/profit-switcher.nix), `followsNixpkgs`/`missingFollows` (tests/flake-input-consistency.nix:53)

### Dead comments + TODOs

- **2,313 commented-out .nix lines** total
- **Worst offenders:** `modules/services/hermes-cli.nix` (94) · `modules/home-manager/niri-config.nix` (64) · `modules/network/cluster-dns.nix` (62) · `hosts/zephyr/services.nix` (61) · `modules/services/mcp-server-registry.nix` (55) · `hosts/zephyr/configuration.nix` (55) · `hosts/usb/configuration.nix` (55)
- **13 TODO/FIXME/HACK markers**

### DRY / pattern duplication

- **88** `systemd.services` declarations (boilerplate candidates)
- **41** `allowedTCPPorts` / `allowedUDPPorts` declarations (mkOptionDefault mandated — verify compliance after P1)
- **41** `openFirewall` / `networking.firewall` references
- **16** `users.users` declarations (data-driven candidate)
- **68** `mkOptionDefault` usages (established pattern — must be enforced)

### Largest files (refactor candidates, descending)

| Lines | File |
|---|---|
| 2,640 | `kubernetes/modules/monitoring.nix` |
| 1,785 | `kubernetes/modules/ai-inference.nix` |
| 1,336 | `kubernetes/modules/host-services.nix` |
| 831 | `modules/home-manager/niri-config.nix` |
| 829 | `modules/home-manager/zen-browser.nix` |
| 657 | `kubernetes/modules/infrastructure.nix` |
| 653 | `modules/services/hermes-cli.nix` |
| 627 | `kubernetes/modules/searxng.nix` |
| 612 | `modules/system/gpu-profile-manager.nix` |
| 610 | `kubernetes/modules/llama-servers.nix` |

### Flake inputs (33 total)

- **Possibly dead / unverified:** `vllm` (already commented in flake.nix), `crane`, `aagl`, `firefox-addons`, `nur`, `scopebuddy`, `nixcord`
- **Stable fallback (verify wiring):** `nixpkgs-2605`
- **Pinned commits (do NOT change in this plan):** `cachyos-kernel`, `sodiboo-niri`, `Lillecarl-easykubenix`, `claude-native`, `llm-agents`, all extracted project flakes

---

## Workstreams

### Phase P0 — Blockers & Latent Bugs (do this week)

**Goal:** Fix parse errors, resolve silent-overwrite bugs in shared modules. **Diff evaluation required** for repeated-key merges — the bug is often that the second key unintentionally overwrites the first.

#### PR 1 — Parse errors & trivial syntax fixes
- [ ] Fix `kubernetes/modules/ai-inference.nix:163:6` (extra brace / unbalanced attrset)
- [ ] Fix `hosts/nexus/supermemory.nix:3:13` (non-Nix prose at top of file)
- [ ] `tests/options-consistency.nix:2` → `inherit (pkgs) lib;`
- **Validation gate:** `nix-instantiate --parse $(find . -name '*.nix') | grep -v 'error:'` returns nothing
- **Branch:** `issue-NN-fix-parse-errors`

#### PR 2 — Repeated-keys resolution (careful merge)
- [ ] Audit each of the 15 flagged files: determine whether keys should be merged, deduplicated, or converted to `lib.mkOptionDefault`
- [ ] Diff closures for zephyr + nexus + forge + sentry against `prod` to confirm no port/services dropped
- [ ] For `systemd.services.x = ...; systemd.services.x = ...` style: merge into single attrset
- [ ] For `allowedTCPPorts = [a]; allowedTCPPorts = [b]` (lists): convert to union list or single combined list
- [ ] Verify `cluster-firewall.nix`, `common-host-defaults.nix`, `host-services.nix` specifically (highest-risk shared modules)
- **Validation gate:** `statix check .` clean AND `nix build .#nixosConfigurations.{zephyr,nexus,forge,sentry}.config.system.build.toplevel` parses all four hosts AND behavioral diff against `prod` shows zero functional change
- **Branch:** `issue-NN-fix-statix-repeated-keys`
- **Effort:** 1–2 hr

---

### Phase P1 — Mechanical Cleansers (end of week)

**Goal:** Bulk-format, dead-code sweep, comment purge, flake-input audit. High-leverage low-risk.

#### PR 3 — Codebase formatting
- [ ] `alejandra .` (rewrites 105 files)
- [ ] Single chore commit: `chore(format): apply alejandra to full repo (#NN)`
- **Validation gate:** `alejandra --check .` returns 0
- **Branch:** `issue-NN-bulk-format`

#### PR 4 — Dead-code elimination
- [ ] `deadnix -e` (auto-removes unused lambda args)
- [ ] Manually remove approved dead let bindings listed in audit findings
- [ ] Fix `kubernetes/modules/gpu-tuning.nix` useless let-in
- [ ] Verify no in-flight refactor is broken (e.g., `niri-config.nix` should not collapse during P2 if it's mid-edit)
- **Validation gate:** `deadnix --check .` clean AND `just check` green
- **Branch:** `issue-NN-cleanup-dead-code`

#### PR 5 — Comment + TODO cleanup (HUMAN REVIEW required)
- [ ] Per-directory human review of 2,313 commented lines (do NOT blanket-delete)
- [ ] Identify and delete load-bearing dead code; **preserve** comments that document non-obvious reasoning
- [ ] Convert all 13 TODO/FIXME/HACK markers: either fix inline (small) or file a GitHub Issue (medium/large) and replace with `# TODO(#MM): …`
- [ ] Files to tackle first (worst offenders): `hermes-cli.nix` (94) · `niri-config.nix` (64) · `cluster-dns.nix` (62) · `zephyr/services.nix` (61) · `mcp-server-registry.nix` (55) · `zephyr/configuration.nix` (55) · `usb/configuration.nix` (55)
- **Validation gate:** Per-file human diff review; `git grep -c '^[[:space:]]*#' modules/ hosts/ kubernetes/ packages/` total drops meaningfully
- **Branch:** `issue-NN-purge-comments`

#### PR 6 — Flake input audit
- [ ] Grep for each candidate input to verify consumers exist:
  ```bash
  grep -rn 'inputs\.\(aagl\|firefox-addons\|crane\|nur\|scopebuddy\|nixcord\)' --include='*.nix' .
  ```
- [ ] Remove unconsumed inputs and the dead commented `vllm` line
- [ ] Verify `nixpkgs-2605` is actually wired (search for `nixpkgs-` in flake.nix and host configs); if not, remove
- [ ] Do NOT remove pinned-commit inputs that are explicitly used (e.g., `cachyos-kernel`, extracted project flakes)
- [ ] Re-run `nix flake update` ONLY if removal changes the lock
- **Validation gate:** `nix flake check` AND `just check` green
- **Branch:** `issue-NN-audit-flake-inputs`
- **Phase P1 effort:** 4–6 hr

---

### Phase P2 — Structural Refactoring (1–2 weeks)

**Goal:** Eliminate DRY boilerplate via helper libraries, split monolith modules.

#### PR 7 — DRY boilerplate helpers (constraint: MUST default to `lib.mkOptionDefault` to satisfy SSH-safety rule)
- [ ] Design `lib/mkSystemService.nix` — wraps the 88 `systemd.services` callsites
  - Default values via `lib.mkOptionDefault` so per-host overrides merge correctly
- [ ] Design `lib/mkFirewall.nix` — replaces the 41 firewall callsites
  - Accepts TCP/UDP port lists + interface trust rules, emits `networking.firewall.*` once
  - Defaults via `lib.mkOptionDefault`
- [ ] Data-drive `users.users` (16 callsites): turn into a lookup table consumed by `modules/system/users.nix`
- [ ] Migrate ONE module as proof of concept (suggest `modules/services/syncthing.nix` — small, isolated)
- [ ] Once proven, migrate remaining callsites one module per commit
- **Validation gate:**
  ```bash
  just check && \
  nixos-rebuild dry-build --flake .#zephyr && \
  nixos-rebuild dry-build --flake .#nexus && \
  nixos-rebuild dry-build --flake .#forge && \
  nixos-rebuild dry-build --flake .#sentry
  ```
  Then SSH smoke-test: `ssh zephyr 'systemctl is-active sshd'` after deploy
- **Branch(es):** `issue-NN-mkSystemService` then `issue-NN-mkFirewall` then `issue-NN-data-driven-users`

#### PR 8 — Split kubernetes/ monoliths (NOT auto-imported — wire explicitly)
- [ ] Create `kubernetes/modules/monitoring/` directory
  - [ ] Extract `prometheus.nix`, `grafana.nix`, `alerting.nix`, `node-exporters.nix` from `monitoring.nix:2,640 lines`
  - [ ] Wire imports through `kubernetes/default.nix`
- [ ] Create `kubernetes/modules/ai-inference/` directory
  - [ ] Extract `gateway.nix`, `privacy-filter.nix`, `llama.nix`, `mcp.nix` from `ai-inference.nix:1,785 lines`
- [ ] Create `kubernetes/modules/host-services/` directory
  - [ ] Extract `csi.nix`, `logs.nix`, `ci-runner.nix`, `debug.nix` from `host-services.nix:1,336 lines`
- [ ] Update `flake.nix` kubernetes import: `kubernetes = import ./kubernetes { … };` should still pick up `kubernetes/default.nix`
- **Validation gate:** `nix flake check` AND dry-build ALL 4 hosts
- **Branch:** `issue-NN-split-kubernetes-monoliths`

#### PR 9 — Split modules/ monoliths (auto-imported — drop file anywhere under `modules/` and it works)
- [ ] `niri-config.nix` (831) → `niri/keybinds.nix` + `niri/theming.nix` + `niri/outputs.nix`
- [ ] `zen-browser.nix` (829) → external `zen-policy.json` as `pkgs/data` + slim HM module
- [ ] `gpu-profile-manager.nix` (612) → per-vendor (`gpu-profile-nvidia.nix`, `gpu-profile-amdgpu.nix`)
- [ ] `llama-servers.nix` (610) → per-variant files
- [ ] `infrastructure.nix` (657), `hermes-cli.nix` (653), `searxng.nix` (627), `sops-secrets-registry.nix` (569), `host-dashboard.nix` (581)
- **Validation gate:** `just check` AND `nix flake check` (auto-import picks them up — no flake wiring change needed)
- **Branch:** `issue-NN-split-modules`
- **Phase P2 effort:** 8–12 hr

---

### Phase P3 — Long-Term Architectural Design (2–3 weeks)

**Goal:** Reorganize kubernetes/ to mirror extracted flakes, audit secrets + auth architecture.

#### PR 10 — Kubernetes app-centric restructure
- [ ] Refactor `kubernetes/modules/` into `kubernetes/apps/<app>/` so each app owns its config + custom sub-manifests
- [ ] Mirror pattern from extracted project flakes (`ai-gateway`, `compute-market`, `caddy-ingress` all use this layout)
- [ ] Verify ingestion of sub-manifests still passes `kubernetes-manifests/AGENTS.md` conventions
- [ ] Run `just k8s-validate` (defined in `flake.nix` apps)
- **Validation gate:** `just k8s-validate` + `kluctl diff` against live cluster
- **Branch:** `issue-NN-k8s-app-restructure`

#### PR 11 — Secrets + auth architecture audit
- [ ] Confirm `sops-secrets-registry.nix` is the single source of truth (no inline `sops.secrets.<name> = { … }` scattered in modules)
- [ ] Validate `casdoor` `mcp-client` scopes per AGENTS.md "Casdoor MCP bridge scopes" known gap (2026-05-14)
- [ ] Remove three stale OIDC secrets flagged in AGENTS.md (2026-05-14 audit): `haven-oidc`, `mission-control-oidc`, `kagent-oidc`
- [ ] Optional: promote `secrets/` into a dedicated `secrets-flake` input for schema versioning (defer if PR10 already too large)
- [ ] Verify auth chain after removing stale secrets: `sso.auth.lan` → `oauth2-proxy` → Casdoor
- **Validation gate:** `just deploy sentry` (sole Vulkan AI inference host) + verify each `.lan` service it depends on still auths correctly
- **Branch:** `issue-NN-secrets-audit`
- **Phase P3 effort:** 10–15 hr

---

## PR Boundary Summary

| PR | Focus | Validation commands |
|---|---|---|
| 1 | Parse errors | `nix-instantiate --parse $(find . -name '*.nix')` |
| 2 | Repeated keys | `statix check`, `nix build` all 4 hosts, prod diff |
| 3 | Format pass | `alejandra --check .` |
| 4 | Dead-code sweep | `deadnix --check .`, `just check` |
| 5 | Comment + TODO purge | **Human diff review**, `git grep` count |
| 6 | Flake input audit | `nix flake check`, `just check` |
| 7 | Helper libs | `just check` + dry-build all 4 hosts + SSH test |
| 8 | K8s monolith split | `nix flake check`, dry-build all 4 hosts |
| 9 | modules/ monolith split | `just check`, `nix flake check` |
| 10 | K8s apps restructure | `just k8s-validate`, `kluctl diff` |
| 11 | Secrets audit | `just deploy sentry` + per-service auth probe |

---

## Cross-Cutting Concerns

1. **GitHub Issue per PR** — AGENTS.md mandate; use `gh issue create --label p1,infra` first
2. **Worktree convention** — `/data/projects/own/nixos-config-NNN` per AGENTS.md
3. **Pre-commit hooks already run `statix check` + `deadnix -f` + `nix-instantiate --parse`** — these gate each PR for free once P0 lands
4. **main → prod deployment gate** — every PR merges to `main`, then `main` → `prod` triggers deploy
5. **Apply `mkOptionDefault` audit after P1:**
   ```bash
   grep -rn 'allowedTCPPorts = \[' --include='*.nix' . | grep -v mkOptionDefault
   ```
   Result must be empty (SSH-safety rule, AGENTS.md)

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Repeated-key merge silently drops port | SSH loss on cluster | Diff evaluation in PR2 — build closures, compare to `prod` |
| Bulk `alejandra` rewrites obscure real changes | Review pain | Single chore commit isolated from logic changes (PR3) |
| Comment purge removes load-bearing documentation | Future confusion | Per-file human review (PR5) |
| `lib/mkFirewall` defaults break SSH | High | `lib.mkOptionDefault` mandatory + smoke-test on staging host first |
| Splitting `kubernetes/modules/monitoring.nix` breaks K8s ingestion | Cluster K8s down | `just k8s-validate` BEFORE merge; never delete the original until validation passes |
| Auto-import picks up unwanted file | Module enabled accidentally | Continue using `modules/lib/collect-modules.nix` deny-list; new files go to known subdirs |
| `nix flake update` triggered by input removal | Lock churn | Avoid `nix flake update` unless removal actually requires it |
| NixOS flake.lock pinned commits change unexpectedly | Re-validation cost | Do not edit any `inputs.X.url = "github:.../<sha>"` lines — preserve pin integrity |
| Concurrent edits to same `.nix` file | Merge conflict | Use submodule split (PR9) to reduce surface area |

---

## Effort Summary

| Phase | PRs | Effort | Risk | Deploy-blocking if missed? |
|---|---|---|---|---|
| **P0** | 1–2 | 1–2 hr | Medium | **Yes** (SSH silently breaks) |
| **P1** | 3–6 | 4–6 hr | Low–Medium | No |
| **P2** | 7–9 | 8–12 hr | Medium | No (helper libs) |
| **P3** | 10–11 | 10–15 hr | High | No |
| **Total** | 11 PRs | **23–35 hr** | — | — |

---

## Success Criteria (overall)

- [ ] `alejandra --check .` returns 0
- [ ] `statix check .` clean
- [ ] `deadnix --check .` clean
- [ ] `nix flake check` clean
- [ ] `just check` green
- [ ] No `.nix` file > 600 lines (down from 2,640)
- [ ] `grep -rn 'allowedTCPPorts = \[' --include='*.nix' . | grep -v mkOptionDefault` returns empty
- [ ] All 13 TODO/FIXME markers tracked as GitHub issues or fixed
- [ ] `< 200` commented-out Nix lines total (down from 2,313)
- [ ] Unverified flake inputs (`aagl`, `firefox-addons`, `crane`, `nur`) confirmed alive or removed
- [ ] All 11 PRs merged to `main`, then promoted to `prod`

---

## Out of Scope

- **Casdoor SSO/OIDC rollout** — separate concern (AGENTS.md notes module exists but is partially enabled)
- **TLS termination on `.lan` services** — HTTP-only on LAN is fine for internal use
- **K3s cluster upgrade** — not touched by audit
- **New extracted project flakes** — current set is sufficient
- **GPU mining configuration optimization** — `pkgs/peakminer.nix` has its own plan
- **Migration to `crane`/`dream2nix`** — leaving for separate initiative if needed

---

## Related Documents

- `.plans/zero-cost-ai-may2026.md` — sister plan for AI routing (similar structure, prior precedent)
- `AGENTS.md` — cluster conventions, safety rules, deployment protocol
- `INFRASTRUCTURE-AUDIT.md` — broader cluster state (some overlap, audit more holistic)
- `STATUS.md` — current cluster operational state
- `DOCS-MAINTENANCE.md` — how plan docs are maintained (Pocock Rule)

---

## Pocock Rule (Plan Doc Maintenance)

This plan MUST be re-verified against reality before being used as a reference. Plans older than 14 days should be re-verified against current cluster state, and completed sections updated with actual outcomes (what changed vs what was planned).

**Re-verification trigger:** Run `just check` against `prod` and confirm all P0/P1 gates are still green. Update `Last Verified` date after each verification pass.

---

*Generated as part of the 2026-07-03 NixOS config audit session. Replace estimated checkboxes with `[x]` as work completes.*
