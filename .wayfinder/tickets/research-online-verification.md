---
type: research
assignee: j_kro-agent (resolved)
blocked-by: []
labels: [wayfinder:research, wayfinder:verification]
status: closed
---

## Question

Research online to confirm the dendritic flake-parts approaches locked on the map
(self-registration, host wiring, withSystem, colmena, checks) before they become the
template for ~90 conversions.

## Resolution — VERIFIED, with one divergence flagged

Sources: flake-parts official docs (options/module-arguments/system), mightyiam/dendritic
README (583★, the canonical pattern definition), dendritic discussion #31 (author's own
answer), colmena docs (flakes tutorial), colmena#60, juspay/colmena-flake, misumisumi/
nixos-k8s-config (real-world flake-parts + colmena).

### CONFIRMED (map decisions hold)

1. **`flake.nixosModules` is the blessed storage** — flake.parts options: "If you want to
   expose reusable configurations, add them to `nixosModules` in the form of modules (no
   `lib.nixosSystem`), so that you can reference them in this or another flake's
   `nixosConfigurations`." Example: `modules = [ ./my-machine/nixos-configuration.nix
   config.nixosModules.my-module ]` — EXACTLY our Layer 2 (host composes
   `config.flake.nixosModules.*`). Note: docs use unqualified `config.nixosModules`
   shorthand; our qualified `config.flake.nixosModules.*` is the real accessor (verified by
   prototype eval).
2. **Every flake-parts module must be imported** — dendritic #31 (author): "write your nixos
   modules wrapped in a flake-parts module... Make sure you import it somehow as a
   flake-parts module, e.g. inside of `imports` in your toplevel `mkFlake` call." = our
   gotcha #1, verbatim. flake-parts only evaluates modules in some imports chain.
3. **`withSystem` is the canonical host evaluator** — flake.parts module-arguments: exact
   pattern `flake.nixosConfigurations.foo = withSystem "x86_64-linux" (ctx@{ config,
   inputs', ... }: inputs.nixpkgs.lib.nixosSystem { specialArgs = {...}; modules = [...];
   })`. Also: `inputs'` (system-preselected inputs) exists — we can use it later; plain
   `inputs` in specialArgs is fine for the bridge.
4. **Checks are perSystem-namespaced** — flake.parts: `flake.checks` = lazy attrset of lazy
   attrset of package (system-keyed); `perSystem.checks.<name>` is the idiomatic write
   location. Confirms the eval-tests research ticket.
5. **Colmena under flake-parts** — colmena#60 (figsoda's comment, widely used):
   "Just change `colmena` to `flake.colmena` and everything works." New colmena uses
   `colmenaHive = colmena.lib.makeHive self.colmena` (direct flake eval, no more
   nix-instantiate legacy). Confirms dissolve Q4: shim now, refactor after all 4 hosts move.
6. **specialArgs pass-thru is a documented anti-pattern** (dendritic README) — confirms our
   bridge is a TEMPORARY migration state and the end-state is minimal specialArgs (only
   inputs), vfioPkgs lives in the vfio feature. Direction locked on inputs ticket = correct.
7. **Feature files as single-feature top-level modules, path names the feature** (dendritic
   README core) — exactly our skeleton.

### DIVERGENCE — decision needed before execute-zephyr-cutover

**Storage namespace: built-in `flake.nixosModules.*` (prototype, verified) vs optional
class-checked `flake.modules.nixos.*` vs custom `deferredModule` options.**

- Canonical dendritic explicitly flags using ONLY built-in options as an anti-pattern
  ("Not declaring options": "Using *only* existing options (such as flake-parts'
  `flake.modules`) for the storage of lower-level modules prevents us from translating our
  mental model of the system into code") and recommends typed `lib.types.deferredModule`
  options (e.g. `options.nixos.base`).
- The flake-parts **optional `modules` module** (`imports.flake-parts.flakeModules.modules`)
  provides `flake.modules.nixos.<name>` with **class type-checking**: "if a Home Manager
  module would be loaded into a NixOS configuration, that becomes a simple type error,
  instead of a complicated message about undeclared options." `flake.nixosModules` (built-in)
  has NO class check — raw lazy attrset of module.
- Relevance to us: we are MID home-manager migration (NixOS-class HM module + standalone HM
  output both live). Class-checking would catch HM-into-NixOS mistakes at the boundary we
  are currently crossing. Cost: import `inputs.flake-parts.flakeModules.modules` in mkFlake
  + key prefix `flake.modules.nixos.` instead of `flake.nixosModules.` — a mechanical change
  across ~90 files and every host list, cheap NOW (prototype stage), expensive later.
- Author's own practice (discussion #31): uses `self.modules.nixos.foobar` namespace with
  `imports = [ self.modules.nixos.barbaz ]` for cross-feature imports — i.e. the
  class-checked `flake.modules.nixos.*` style, NOT the built-in.

**Recommendation: adopt `flake.modules.nixos.<name>`** (class-checked) for the cutover; keep
`flake.nixosModules` as thin aliases only if some external consumer needs them. Presenting to
j_kro as A/B on the next grill.

### Also noted (post-migration polish, not blockers)

- **enable options anti-pattern** (dendritic): "In most cases, importing a module should
  enable the feature that it provides." Our verbatim-converted modules keep their legacy
  `enable` options — fine for migration; a future cleanup pass can drop them.
- Cross-feature imports `imports = [ self.modules.nixos.barbaz ]` are canonical; our
  prototype used cross-feature READS (`config.services.k3s-cluster.enable or false`) — both
  valid, reads are more decoupled. Keep reads unless a feature genuinely needs the other
  module's option DEFINITIONS (rare).
- juspay/colmena-flake (13★) = ready-made flake-parts module for colmena deployment options
  decoupled under `flake.colmena-flake.deployment.*` — alternative to makeHive for the
  post-migration colmena refactor; revisit at shim-dissolve time.
