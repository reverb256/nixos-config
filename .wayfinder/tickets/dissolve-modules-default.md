---
type: grilling
assignee: j_kro-agent (resolved)
blocked-by: [research-flake-parts-mechanics]
labels: [wayfinder:grilling]
status: closed
---

## Question

`modules/default.nix` is a hardcoded ~90-path central registry imported by every host. In the
dendritic pattern with explicit (non-import-tree) wiring, how do the ~90 shared modules get
registered as `self.nixosModules.*`? (Full question in the map.)

## Resolution

**CLOSED — convention locked via grilling (HITL).**

1. **Registry = `modules/default.nix` becomes a flake-parts aggregator (B):** it lists the
   feature files as flake-parts module paths (`{ imports = [ ./services/k3s-cluster.nix ... ]; }`),
   imported once by flake.nix as `./modules/default.nix`. Root flake stays short; registry
   colocated with modules; consistent with the host registry decision
   (`modules/hosts/default.nix`).
2. **Self-registering files (A):** each feature file owns its registration —
   `flake.nixosModules.<name> = <old body>` (file-name key). Aggregator is a dumb path list.
   "Every file is a module" holds; the ~90-line key→path map is NOT recreated.
3. **Non-features imported by path in `base` (B):** `network-constants.nix`,
   `common-host-defaults.nix`, profile plumbing etc. stay plain NixOS modules, imported by path
   inside `nixosModules.base`. Classification rule: *"would a host ever import this by name in
   its feature list?"* — host-pickable → feature (self-register); only-base → plumbing (path
   import). `nixosModules.*` stays a feature namespace.
4. **`common-modules-list.nix` + colmena stay as a compatibility shim (B):** the shim is the
   backbone keeping nexus/forge/sentry on classic wiring while zephyr proves dendritic first.
   Refactor `colmena.nix` to consume `config.flake.nixosModules.*`/`config.flake.nixosConfigurations`
   (not `self.outputs.colmena`) and dissolve the shim only AFTER all 4 hosts are dendritic.
   `flake-input-consistency` test update lands with the dissolution (see eval-tests ticket).

**Unblocks:** prototype-reference-conversion (registry + base aggregate + shim strategy),
inputs-specialargs-plumbing (network-constants remains plumbing-by-path — feeds its answer).
