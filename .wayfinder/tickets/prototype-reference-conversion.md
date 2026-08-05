---
type: prototype
assignee: j_kro-agent (resolved)
blocked-by: [convention-module-skeleton, convention-host-wiring, dissolve-modules-default]
labels: [wayfinder:prototype]
status: closed
---

## Question

Produce a **reference end-to-end conversion** of ONE real feature module + the zephyr host, in
dendritic flake-parts form, as a concrete artifact the other ~90 conversions follow.

## Resolution

Built the reference artifact at **`wayfinder-prototype/`** on throwaway branch
`wayfinder/prototype-dendritic` (NOT deployed; planning asset). 17 files, self-contained
mini-flake, real module content copied from the repo.

**Verified by execution** (`nix flake check --no-build` — ALL outputs check, incl.
`nixosConfigurations.zephyr` + 7 registered `nixosModules.*`):
- `nix eval .#nixosConfigurations.zephyr.config.networking.hostName` → `"zephyr"`
- `.#...config.networking.cluster.kubernetes.vip` → `"10.1.1.120"` (plumbing via base)
- `.#...config.systemd.services.desktop-oom-protect.description` → the oom-protection text
  (cross-feature dep works; k3s-cluster option exists w/ default false)
- `.#...config.services.keepalived-vip.vip` → `"10.1.1.120"` (option default reads cluster
  constants through self-registered feature)

**Files (all real, no stubs):**
- `flake.nix` — `mkFlake { inherit inputs; }`; `imports` = base + feature files + host
  registry; systems = x86_64-linux
- `modules/services/keepalived-vip.nix` — canonical skeleton: `{ inputs, ... }:` outer head,
  `flake.nixosModules.keepalived-vip = <old body verbatim>`, options+config in ONE module
- `modules/system/oom-protection.nix` — same skeleton; demonstrates CROSS-FEATURE READ
  (`config.services.k3s-cluster.enable or false`) → host must import both (loud eval error if not)
- `modules/hosts/zephyr/default.nix` — two-layer: `flake.nixosModules.zephyrConfig` (identity
  FIRST `networking.hostName`, body blob) + `flake.nixosConfigurations.zephyr = withSystem
  ... nixosSystem { specialArgs = { inherit inputs; }; modules = [ base, zephyrHardware,
  zephyrConfig, keepalived-vip, oom-protection, vfio-gamepass, peakminer ]; }`. Host file
  itself nests imports of its host-private modules so they self-register.
- `modules/hosts/zephyr/hardware.nix` — `zephyrHardware` aggregate; hardware-configuration.nix
  = plain path import (never keyed); minimal stand-in labeled as machine-generated data
- `modules/hosts/zephyr/vfio-gamepass.nix`, `peakminer.nix` — host-private modules; vfio
  carries `vfioPkgs` as an OPTION (Q1=A: not in specialArgs)
- `modules/base.nix` — `flake.nixosModules.base` aggregate; imports plumbing (network-constants,
  common-host-defaults, system/*) BY PATH
- `modules/network-constants.nix` + system stand-ins — minimal stand-ins so the reference
  evaluates; real files stay put, imported by path in real conversion

**Pattern lessons discovered during build (gotchas):**
1. **Every flake-parts module must appear in SOME imports chain** — base.nix and host-private
   files initially didn't self-register because nothing imported them. Base joins flake.nix's
   imports; host-private files join the host file's own `imports` (nested import).
2. **`config.flake.nixosModules.*` references belong at Layer 2 only** — inside zephyrConfig
   (a NixOS module), `config` is NixOS config, NOT flake-parts config → `attribute 'base'
   missing` style eval errors. The feature list lives in the `modules = [...]` list of
   nixosSystem, where `config` IS flake-parts config.
3. **Path imports are relative to the importing file** — base.nix at modules/base.nix uses
   `./network-constants.nix`, not `../../`.

**Storage namespace DECIDED: B (class-checked `flake.modules.nixos.*`).** Added
`inputs.flake-parts.flakeModules.modules` to mkFlake imports; every feature registers
under `flake.modules.nixos.<name>` (not built-in `flake.nixosModules.*`); hosts import via
`config.flake.modules.nixos.<name>`. Re-verified: `nix flake check` ALL outputs pass +
nix eval of hostName/VIP/keepalived/oom-protection through the B namespace. Class-checking
catches HM-into-NixOS mistakes — directly useful mid home-manager migration. This is the
template every later conversion copies. Remaining rollout: `rollout-order-safety`
→ `execute-zephyr-cutover`.
