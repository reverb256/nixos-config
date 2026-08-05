---
type: grilling
assignee: j_kro-agent (resolved)
blocked-by: [research-flake-parts-mechanics]
labels: [wayfinder:grilling]
status: closed
---

## Question

How do **`inputs` / `specialArgs` / cluster constants** plumb into modules after conversion?
(Full question in the map.)

## Resolution (in progress)

**Q1 — specialArgs bridge = `{ inherit inputs; }` ONLY (A, user-corrected).** The bridge does
NOT carry `vfioPkgs`. Modules that reference `vfioPkgs` (the VFIO GPU VM package set) get it
resolved inside the vfio feature (option or perSystem packages) — the feature owns its
artifacts. Cutover is a re-wire for `inputs`-only modules; `vfioPkgs` converts with the vfio
feature. Hygiene pass (removing inner `inputs` args + shrinking specialArgs) still comes after
all 4 hosts are dendritic (skeleton Q6).

**Q2 — `network-constants` content unchanged (A).** Stays a plain plumbing module imported by
path in `base` (dissolve Q3); modules read `config.networking.cluster` exactly as today. Cluster
constants are NixOS config data, not flake outputs; no move to flake layer, no split.

**Q3 — home-manager: STANDALONE IS THE TARGET, migration is IN-FLIGHT (corrected).**
Verified against repo + `nixos-home-manager-layering` skill + session history (2026-08-02):
- The cluster runs the **3-layer model** (NixOS / HM standalone / nix profile). The LIVE HM
  switch path on zephyr is standalone: `~/.config/home-manager/flake.nix` (a wrapper flake)
  imports `modules/home-manager/standalone.nix` from its `nixos-config` input — canonical
  `github:reverb256/nixos-config` (origin/main), NEVER `~/Projects/` or bare `/etc/nixos`
  (j_kro 2026-08-02 ALL-CAPS directive).
- PR #339 renamed `homeConfigurations` keys to `j_kro@<host>` (`just hm-switch` runs
  `home-manager switch --flake .#j_kro@<host>`); bare `.#zephyr` FAILS.
- `modules/system/home-manager.nix` (NixOS-class path, imported by common-modules-list.nix +
  modules/default.nix) is the **legacy path being phased out** — NOT a permanent sibling. The
  migration direction: user-env lives in standalone HM; NixOS-class extras
  (`hermesWrappedBin`, `noctaliaPackage`, niri-config) are being unwound.
- `shared-leaf-modules.nix` is the SSOT leaf list both paths import (issue #338 / PR #339).

Dendritic implications (must be on the map):
- **`flake.homeConfigurations` MUST survive the flake-parts conversion** — it is the standalone
  build source; under flake-parts it becomes `flake.homeConfigurations` (freeform, merges),
  still keyed `j_kro@<host>`. Its `extraSpecialArgs` uses `vfioPkgs` (flake.nix:271) → per
  Q1=A, resolve `vfioPkgs` from the vfio feature.
- **`modules/home-manager/standalone.nix` + the wrapper flake contract must stay stable** — the
  zephyr wrapper imports `standalone.nix` from the repo; the dendritic cutover must not move or
  break that path, or `home-manager switch` breaks cluster-wide.
- **The NixOS-class HM module's removal is a separate in-flight workstream** — during the
  dendritic cutover it stays plumbing-by-path (dissolve Q3), consistent with "mid-migration";
  its eventual deletion lands with the standalone-migration completion, not the dendritic one.
- Concurrent-workstream note: the standalone HM migration and the dendritic migration are
  BOTH in flight; they interact at `flake.homeConfigurations` + `modules/home-manager/*` paths.

## Open sub-questions (for prototype ticket)

1. Standalone `homeConfigurations` migration details: how it declares hosts, how vfioPkgs
   resolves, whether the `hosts` map comes from `config.flake.nixosConfigurations` or the
   host-inventory contract.
2. Whether `flake.homeConfigurations` stays in the nixos-config flake at all vs moving to the
   wrapper flake (the zephyr wrapper currently imports standalone.nix from this repo) —
   decide in prototype or a dedicated ticket if it grows.
