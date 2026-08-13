---
type: handoff
assignee: j_kro-agent (executed 2026-08-13)
blocked-by: [rollout-order-safety, prototype-reference-conversion, research-online-verification]
labels: [wayfinder:execute, wayfinder:handoff]
status: closed
---

> **COMPLETED 2026-08-13 (issue #397).** Full dendritic migration ran to completion:
> zephyr → nexus → forge → sentry cutover, then classic-shim dissolution. Wiring is the
> two-layer Variant B pattern (`modules/hosts/<host>/default.nix` + `lib/dendritic-host.nix`).
> Commits `3d78210b` (phase-1b merge) and `3da95702` (dissolution). This checklist was the
> template reused for the other three hosts.

## Question

Produce the concrete execution handoff for cutting over **zephyr** (host #1 of the
zephyr→nexus→forge→sentry sequence). This ticket is the HITL gate: every step is written
but NONE executes until j_kro green-lights (Standing Rule: no commit/deploy without say-so).

## Execution checklist — zephyr cutover (host #1)

> Pre-conditions (already true): branch `wayfinder/prototype-dendritic` exists. The
> dangling k3s guard (`services.k3s-cluster.enable = lib.mkForce false`) that was
> applied to `hosts/zephyr/configuration.nix` was REMOVED 2026-08-04: the option
> exists only in `modules/services/k3s-cluster.nix`, which zephyr never imports
> (nexus:46/forge:79/sentry:24 only), so mkForce could never eval. Absence-of-import
> IS the guard (topology contract; `tests/k3s-topology-evidence.nix:94` asserts it).
> `gaming-mining-coordinator.nix` deleted. The verified
> B-template prototype lives at `wayfinder-prototype/` (throwaway, NOT this branch).
> The PLAN below converts the REAL zephyr config on the cutover branch — it does not deploy
> the throwaway prototype.

### STEP 0 — Pre-flight (read-only, no mutation)
- [ ] `git status` on `wayfinder/prototype-dendritic`: confirm only expected diffs
      (k3s guard + coordinator delete). No stray edits.
- [ ] Confirm `colmena exec zephyr -- nixos-rebuild list-generations` shows current good
      generation — that is the rollback target (rollout Q3).
- [ ] Snapshot current zephyr running config hash for comparison post-cutover.

### STEP 1 — Convert zephyr to dendritic (on the cutover branch, NOT main)
For EACH zephyr-relevant module, apply the B template (from `prototype-reference-conversion`):
- [ ] **flake.nix**: replace classic `outputs` body with
      `inputs.flake-parts.lib.mkFlake { inherit inputs; } { systems = [x86_64-linux]; imports = [ inputs.flake-parts.flakeModules.modules ./modules/base.nix ./modules/services/keepalived-vip.nix ./modules/system/oom-protection.nix ... ./modules/hosts/default.nix ]; }`
      (every self-registering feature + base + host registry listed; ~90 files ported over
      the full migration — for THIS host step, port what zephyr actually imports).
- [ ] **features** (shared, used by zephyr): wrap body in
      `{ inputs, ... }: { flake.modules.nixos.<name> = <old body verbatim>; }` — no logic
      change, uniform head, options+config in one module (skeleton Q5→B).
- [ ] **base.nix**: `flake.modules.nixos.base` aggregates plumbing by path
      (network-constants, common-host-defaults, system/*) (dissolve Q3→B).
- [ ] **hosts/zephyr/default.nix** (NEW, two-layer):
      - Layer 1 `flake.modules.nixos.zephyrConfig` — identity FIRST
        (`networking.hostName = "zephyr"`) + config-body blob (host-wiring Q1→B, Q2→C-then-B).
      - Layer 2 `flake.nixosConfigurations.zephyr = withSystem "x86_64-linux" ({ config, ... }: inputs.nixpkgs.lib.nixosSystem { specialArgs = { inherit inputs; }; modules = [ config.flake.modules.nixos.base config.flake.modules.nixos.zephyrHardware config.flake.modules.nixos.zephyrConfig <shared features zephyr uses> config.flake.modules.nixos.vfio-gamepass config.flake.modules.nixos.peakminer ]; })`.
      - Imports its host-private modules (vfio-gamepass, peakminer, hardware) so they
        self-register (gotcha #1).
- [ ] **hosts/default.nix**: add `./zephyr` to the aggregator (host-wiring Q7→B).
- [ ] **modules/default.nix**: becomes the flake-parts aggregator path-list (dissolve Q1→B),
      imported once by flake.nix.
- [ ] **common-modules-list.nix**: REMOVE zephyr from the classic shim list (rollout Q3:
      isolated per-host commit). Do NOT delete the file yet (sentry/forge/nexus still classic).
- [ ] **`flake.homeConfigurations`** survives unchanged (keyed `j_kro@zephyr`, PR #339) —
      standalone HM path intact (inputs Q3). vfioPkgs resolved from the vfio feature.

### STEP 2 — Verify by evaluation (no deploy)
- [ ] `nix flake check --all-systems` → ALL outputs pass (incl. nixosConfigurations.zephyr
      + every registered flake.modules.nixos.*).
- [ ] `nix build .#nixosConfigurations.zephyr.config.system.build.toplevel` → builds.
- [ ] `nix eval .#nixosConfigurations.zephyr.config.networking.hostName` → `"zephyr"`.
- [ ] k3s on zephyr: `nix eval .#nixosConfigurations.zephyr.config.services.k3s-cluster.enable`
      → MUST ERROR ("does not provide attribute ... k3s-cluster.enable"). The option
      does not exist on zephyr (absence-of-import IS the guard); a successful `false`
      would mean k3s-cluster.nix was wrongly imported. `tests/k3s-topology-evidence.nix`
      asserts the non-import. Cross-check nexus: `nix eval ...nexus.config.services.k3s-cluster.enable`
      → `true` (classic hosts unaffected).

### STEP 3 — Commit (isolated per-host)
- [ ] `git add -A` is FORBIDDEN (Execution Discipline). Stage only the zephyr cutover files.
- [ ] `git commit -m "feat(zephyr): convert to dendritic flake-parts (host #1/4)"`
- [ ] `git push origin wayfinder/prototype-dendritic` (or a dedicated `execute-zephyr`
      branch — confirm with j_kro which to push).

### STEP 4 — Deploy (HITL gate — awaits j_kro GO)
- [ ] `colmena apply --on zephyr` (or local `sudo nixos-rebuild switch` if zephyr is the
      console host). **Does not run until j_kro says GO.**

### STEP 5 — Post-deploy Full gate (rollout Q2)
- [ ] `colmena exec zephyr -- systemctl is-system-running` → `running` (or `degraded` with
      only known-benign units).
- [ ] Feature assertions for zephyr:
      - [ ] Desktop session reachable (niri/Wayland up).
      - [ ] `systemctl is-active k3s` → `inactive`/`unknown` (guard holds post-deploy).
      - [ ] Noctalia/desktop services not crash-looping (the VRAM-OOM root cause is separate
            and UNMITIGATED — note it, do not let it block cutover).
- [ ] Boot is clean: no failed units from the conversion.

### STEP 6 — Declare done / rollback
- [ ] ALL green → zephyr cutover DONE. Mark this ticket closed. Next: `execute-nexus-cutover`
      (host #2), which reuses this exact checklist with nexus's feature set + the builder
      build-assertion.
- [ ] ANY red → **rollback**: `colmena exec zephyr -- nixos-rebuild switch --rollback`
      (or boot previous on console). Investigate, do NOT proceed to nexus.

## Out of scope (later tickets)
- nexus / forge / sentry cutovers (same checklist, host-specific feature assertions).
- Shim dissolve (after all 4 dendritic): colmena `makeHive self.colmena` + delete
  common-modules-list.nix; modules/default.nix aggregator stays.
- `flake-input-consistency` test update at dissolve time.

## Blockers / notes
- Noctalia VRAM-OOM root cause (NVRM `[NV_ERR_NO_MEMORY]`) is UNMITIGATED and independent of
  this cutover — it must not be conflated with conversion success/failure.
- alloy.service syntax bug (`config.alloy:22:51` `;` vs `,`) is a SEPARATE chronic issue.
- forge's miners are revenue-critical — nexus (host #2) MUST prove the builder still builds
  before forge (host #3) proceeds (rollout ORDER).
