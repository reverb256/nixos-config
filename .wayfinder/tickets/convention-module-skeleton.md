---
type: grilling
assignee: j_kro-agent (resolved)
blocked-by: [research-flake-parts-mechanics]
labels: [wayfinder:grilling]
status: closed
---

## Question

Define the **canonical module skeleton**: how does a current NixOS module become a flake-parts
dendritic module? (Full question in the map.)

## Resolution

**CLOSED — convention locked via grilling (HITL).** The canonical skeleton for this repo:

```nix
# modules/services/foo.nix — every module file self-registers.
# Outer head: uniform `{ inputs, ... }:`.
{ inputs, ... }: {
  # perSystem ONLY when the feature builds artifacts (packages/devShells/checks).
  # perSystem = { pkgs, ... }: { packages.foo = ...; };
  flake.nixosModules.foo = { config, lib, pkgs, ... }: {
    # old body verbatim — zero edits: options + config stay in ONE inner module.
    options.services.foo = { ... };
    config = lib.mkIf cfg.enable { ... };
  };
}
```

Decisions (Q1–Q7):
1. **Key name = file name verbatim, kebab-case** (`modules/services/k3s-cluster.nix` →
   `nixosModules.k3s-cluster`). Collisions are loud.
2. **`options` + `config` in one inner module** — verbatim wrap, zero body edits.
3. **Outer head uniformly `{ inputs, ... }:`** — structurally identical files.
4. **`perSystem` only when the feature produces artifacts**; migrate the repo's existing
   `packages.x86_64-linux.*` / `checks.x86_64-linux.*` into the owning feature files'
   `perSystem` blocks (A+C).
5. **Cross-feature reads: explicit dependency imports in host wiring (B)** — a feature that
   reads another's options requires the host to import both; missing dep = loud eval error.
   Prototype ticket documents a transitive-dep checklist.
6. **Two-phase inputs handling (A):** functional cutover first (zero body edits;
   `specialArgs = { inherit inputs; }` bridges), then a dedicated cleanup pass removing inner
   `inputs` args after all 4 hosts are dendritic.
7. **File layout (C):** hosts move to `modules/hosts/<host>/default.nix`; feature files stay
   in place, gain wrapper in place. Optional feature-tree flatten later.

**Unblocks:** convention-host-wiring (Q5 dependency rule feeds host list), dissolve-modules-default
(decision 7: features stay put, only hosts move), prototype-reference-conversion (canonical
skeleton + dep checklist).
