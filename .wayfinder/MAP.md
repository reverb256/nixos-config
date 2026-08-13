# Wayfinder Map: Full flake-parts dendritic migration

Labels: `wayfinder:map`

## Destination

Convert **`nixos-config`** (the cluster flake, 4 hosts: zephyr/nexus/forge/sentry) to the
**full flake-parts dendritic pattern**: every `.nix` file becomes a flake-parts module
(`flake.nixosModules.<feature>` + optional `perSystem`), and each host becomes a tiny
`modules/hosts/<host>/default.nix` that **explicitly** imports the features it wants.
Incremental, **host-by-host** (zephyr first as proving ground), **explicit `nixosModules.*`
wiring** — NOT import-tree auto-discovery, because hosts are heterogeneous (zephyr has a GPU
VM, forge mines on 2×4060, nexus builds, sentry is control-plane/inference).
**roguelite-project is NOT in scope** (separate flake-utils Godot flake — leave it).

## Notes

- Domain: NixOS / flakes / flake-parts / dendritic pattern (vic/dendritic, vimjoyer video 76).
- Skills every session should consult: `wayfinder`, `nixos-module-organization`,
  `nixos-config-maintenance-cleanup`, `nixos-flake-eval-debugging`.
- Standing preferences: cluster is LIVE (4 nodes) — every cutover must be reversible via
  `nixos-rebuild` generations; never break the running cluster. User said "don't build/deploy"
  during planning — this map is planning only, no execution until the route is clear.
- Current state: classic flake. `flake-parts` is only a transitive dep. `modules/default.nix`
  is a hardcoded ~90-path central registry imported by every host. zephyr's `configuration.nix`
  is 1120 lines (imports + big `config` body).
- Just resolved: k3s OFF zephyr (deleted orphaned gaming-mining-coordinator module, added
  `services.k3s-cluster.enable = lib.mkForce false` guard) — not yet deployed.

## Decisions so far

<!-- index — one line per closed ticket; zoom the link for detail -->

- [research-eval-tests-compat](tickets/research-eval-tests-compat.md) — CLOSED: 8/18 tests break on migration, all because they readFile/pathExists the classic `hosts/<h>/…` layout or grep literal `flake.nix`/`modules/default.nix` strings that `mkFlake` dissolves; `flake.nixosConfigurations.<host>` is unaffected under mkFlake; `nix flake check` moves to `perSystem.checks`. Recommended: migrate `k3s-topology-evidence` to real eval (`self.nixosConfigurations.zephyr.config.services.k3s-cluster.enable == false`) BEFORE the dendritic move. Also caught a real bug: zephyr's k3s guard was `services.services.k3s-cluster.enable` (nested too deep, no-op) — fixed to `k3s-cluster.enable = lib.mkForce false` inside the services block.
- [research-flake-parts-mechanics](tickets/research-flake-parts-mechanics.md) — CLOSED: canonical pattern confirmed — `mkFlake { inherit inputs; }`; `flake.nixosConfigurations.<host>` merges across modules (no central list); `perSystem` + `flake` are siblings; `inputs`/`self`/`withSystem`/`moduleWithSystem` injected into every module; `systems = import inputs.systems` works verbatim (input already wired); explicit wiring = wrap old module body in `flake.nixosModules.<name> = <old fn>` (zero body edits), host default.nix lists `config.flake.nixosModules.*` via `withSystem`. Gotchas: `colmenaHive` must read `config.flake.colmena` (avoid self-ref cycle), `checks`→`perSystem.checks`, `pkgsWithOverlay`→`perSystem.nixpkgs`, `hosts/<h>/*.nix` leaf files can stay path imports, keep `specialArgs={inherit inputs}` during transition, shim module keeps other 3 hosts classic meanwhile.
- [convention-module-skeleton](tickets/convention-module-skeleton.md) — CLOSED: canonical module shape locked — uniform outer head `{ inputs, ... }:`; inner module wraps old body verbatim in `flake.nixosModules.<name>` (file-name key, kebab-case); options+config in ONE inner module; `perSystem` only when the feature builds artifacts (migrate existing packages/checks into owning feature's perSystem); cross-feature reads require explicit dependency imports in host wiring (missing dep = loud eval error); two-phase inputs (functional cutover first w/ specialArgs bridge, then cleanup pass); file layout = hosts move to `modules/hosts/<host>/default.nix`, features stay in place.
- [convention-host-wiring](tickets/convention-host-wiring.md) — CLOSED: host wiring locked — two-layer host file (`nixosModules.<host>Config` = content incl. identity-first `networking.hostName`, `flake.nixosConfigurations.<host>` = evaluates via withSystem); config body split by seams now (peakminer/monitoring/desktop) rest as blob for later cleanup; >1 host uses a module = shared feature, exactly 1 = `modules/hosts/<host>/<feature>.nix`; every host imports `base` aggregate + `<host>Hardware` aggregate (hardware-configuration.nix stays a plain path import, never keyed); host registry = `modules/hosts/default.nix` aggregator imported once by flake.nix.
- [dissolve-modules-default](tickets/dissolve-modules-default.md) — CLOSED: registry locked — `modules/default.nix` becomes a flake-parts aggregator (path list, imported once by flake.nix); feature files self-register `flake.nixosModules.<name>` (file-name key); non-features (network-constants, common-host-defaults, profiles) stay plain modules imported by path in `base` (classification: "would a host import this by name?"); `common-modules-list.nix` + classic colmena stay as compatibility shim until all 4 hosts are dendritic, then colmena refactors to `config.flake.nixosModules.*` and shim dissolves.
- [inputs-specialargs-plumbing](tickets/inputs-specialargs-plumbing.md) — CLOSED: plumbing locked — bridge = `specialArgs = { inherit inputs; }` ONLY (vfioPkgs NOT bridged; moves into vfio feature as option/perSystem); `network-constants` content unchanged (plumbing by path in base, read via config.networking.cluster); **home-manager: STANDALONE IS THE TARGET, migration IN-FLIGHT** — `flake.homeConfigurations` MUST survive conversion (still keyed `j_kro@<host>` per PR #339; vfioPkgs resolved from vfio feature), `modules/home-manager/standalone.nix` + zephyr wrapper-flake contract must stay stable, NixOS-class `modules/system/home-manager.nix` stays plumbing-by-path during cutover but its removal is a separate in-flight workstream (3-layer model; j_kro 2026-08-02 directive: wrapper input = github:reverb256/nixos-config only).
- [prototype-reference-conversion](tickets/prototype-reference-conversion.md) — CLOSED: reference artifact built at `wayfinder-prototype/` (branch `wayfinder/prototype-dendritic`, NOT deployed) — 17 files, real content; **verified by execution** (`nix flake check` ALL outputs + `nix eval` of hostName/VIP/oom-protection/keepalived-vip through the wiring). Gotchas: (1) every flake-parts module must appear in some imports chain (base → flake.nix imports; host-private → host file's own imports), (2) `config.flake.nixosModules.*` refs only valid at Layer 2 (inside a NixOS module `config` is NixOS config), (3) path imports relative to importing file. Template for all ~90 conversions.
- [research-online-verification](tickets/research-online-verification.md) — CLOSED (research): **all approaches CONFIRMED online** — flake.parts docs (nixosModules storage + withSystem + perSystem checks), dendritic README + #31 (imports-chain requirement, specialArgs anti-pattern), colmena docs/#60 (`flake.colmena`, `makeHive self.colmena`). **DIVERGENCE RESOLVED → B**: storage namespace = class-checked `flake.modules.nixos.*` (built-in `flake.nixosModules.*` rejected — no class check). Applied + re-verified in prototype.
- [rollout-order-safety](tickets/rollout-order-safety.md) — CLOSED (grilled, 4 choices): **ORDER zephyr → nexus → forge → sentry** (builder 2nd for early stabilization; forge's miners 3rd after builder proven; sentry/k3s-brain last). **GATE = Full** (flake check + nix build toplevel + colmena apply + is-system-running + feature assertions: miners hashing on forge, k3s Ready on sentry; next host ONLY after all green, no batching). **ROLLBACK = per-host generation** (`colmena exec <host> -- nixos-rebuild switch --rollback`; isolated per-host commits so a bad host reverts without touching others). **SHIM dissolves only after all 4 dendritic** (flip colmena to `makeHive self.colmena` reading `flake.modules.nixos.*` + `flake.nixosConfigurations.*`, delete common-modules-list.nix, modules/default.nix = aggregator stays). Uses verified B template.
- [execute-zephyr-cutover](tickets/execute-zephyr-cutover.md) — CLOSED (executed 2026-08-13): concrete 6-step handoff for host #1 (reused for nexus/forge/sentry). Full migration + shim dissolution complete — commits 3d78210b (phase-1b) + 3da95702 (dissolution). STEP 0 preflight (read-only) → STEP 1 convert REAL zephyr on the cutover branch using B template → STEP 2 eval-verify (flake check + build + hostName + k3s guard false) → STEP 3 isolated commit (NO `git add -A`) → STEP 4 deploy = **awaits j_kro GO** → STEP 5 Full post-deploy gate (is-system-running + k3s inactive + desktop up) → STEP 6 done-or-rollback. Separate concerns noted: Noctalia VRAM-OOM unmitigated, alloy `;` bug, forge miners revenue-critical (nexus must prove builder first). Reuses this checklist for nexus/forge/sentry.
  - **GitHub**: tracking issue [#397](https://github.com/reverb256/nixos-config/issues/397) (`wayfinder:map`) = canonical map; child [#398](https://github.com/reverb256/nixos-config/issues/398) (`wayfinder:task`, labeled "execute-zephyr-cutover (host #1/4, HITL)") = this ticket, linked `Part of #397`. GH is now canonical; `.wayfinder/` is the in-repo backup snapshot. Created 2026-08-04.

## Not yet specified

- Exact shape of `perSystem` packages that currently live outside modules (e.g. the
  `godot-mcp-server` `callPackage` in roguelite flake, any top-level `packages.*`).
- How `home-manager` coexists with dendritic flake-parts — **RESOLVED by inputs-specialargs-plumbing**: standalone HM is the target (3-layer model); `flake.homeConfigurations` (keyed `j_kro@<host>`) survives under flake-parts freeform; NixOS-class `modules/system/home-manager.nix` stays plumbing-by-path during cutover. OPEN: whether `flake.homeConfigurations` stays in this flake vs moving to the zephyr wrapper flake; how the `hosts` map feeds standalone HM (see prototype ticket sub-questions).
- Whether `flake.lock` changes (new `flake-parts`/`import-tree` inputs) need a coordinated
  lockfile update across the cluster before first cutover.
- CI / colmena: does the deploy path (`colmena deploy`) change when hosts move to
  `flake.nixosConfigurations.*` exposed via `flake.`? (Likely no — same attribute path.)

## Out of scope

<!-- work ruled beyond the destination -->

- **Flat features reorg** (`modules/features/<name>.nix` + `modules/hosts/` + `modules/pkgs/`) — user explicitly deferred to a **post-migration follow-up effort**. THIS migration keeps feature files in place (convention-module-skeleton Q7 → C); only hosts move to `modules/hosts/<host>/default.nix`. The flat reorg returns as a fresh effort once the dendritic cutover is complete.
