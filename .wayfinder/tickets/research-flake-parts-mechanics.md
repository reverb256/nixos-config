---
type: research
assignee: resolved
blocked-by: []
labels: [wayfinder:research]
status: closed
---

## Question

Confirm the exact flake-parts dendritic mechanics for a multi-host NixOS cluster flake.
(Full question in the map's ticket.)

## Resolution

**CLOSED — research complete.** Code-level findings (full report:
`/home/j_kro/.hermes/cache/delegation/subagent-summary-0-20260804_013350_908513.txt`):

1. **Entry point:** `flake-parts.lib.mkFlake { inherit inputs; } <module>` — the module can be
   an attrset or function; everything (even `systems`) can live in imported files.
2. **Hosts:** `flake.nixosConfigurations.<host>` merges across modules — no central host list,
   no `mapAttrs` glue. Never in `perSystem`; use `withSystem "x86_64-linux"` when a host needs a
   perSystem package. `nixosConfigurations` is not per-system.
3. **perSystem + flake coexist as siblings**, both in the same file. Current `checks.x86_64-linux`
   and `packages.x86_64-linux.*` map 1:1 to `perSystem.checks` / `perSystem.packages`.
4. **inputs/self injection:** flake-parts injects `inputs`, `self`, `getSystem`, `withSystem`,
   `moduleWithSystem`, `lib`, `config`, `options` into every module; `perSystem` additionally gets
   `pkgs`, `system`, `inputs'`, `self'`. Dendritic doctrine: stop passing `inputs` via
   `specialArgs`; close over at flake-parts layer instead. Pragmatic for THIS repo: keep
   `specialArgs = { inherit inputs; }` during migration, remove feature-by-feature (hundreds of
   modules take `inputs` as NixOS arg).
5. **systems:** declare once at top level. Repo already has `inputs.systems` (nix-systems, flake
   false) → `systems = import inputs.systems;` works verbatim.
6. **Explicit wiring (the key mechanical rule):** wrap the old module's function body in
   `flake.nixosModules.<name> = <old function>;` with the outer file taking flake-parts args —
   **zero body edits**. Host = `modules/hosts/<host>/default.nix` building
   `flake.nixosConfigurations.<host> = withSystem ... nixosSystem { modules = [ config.flake.nixosModules.<feature> ... ]; }`.
   `config.flake.nixosModules.*` is the in-evaluation self-reference (preferred); `self.nixosModules.*`
   is the external-consumer form.

**Repo-specific gotchas:**
- `colmena`/`colmenaHive` are non-standard outputs; `flake` is freeform so they work, but
  `colmenaHive` must read `config.flake.colmena` (not `self.outputs.colmena`) to avoid cycles.
  `commonModules` arg disappears → refactor to consume `config.flake.nixosModules.*`.
- `checks` block → `perSystem.checks` (gets `pkgs` free; `mkCheck` throw-on-failure unchanged).
- `pkgsWithOverlay` isn't a schema attr — use `perSystem.nixpkgs` / `_module.args.pkgs`.
- `contracts/host-inventory.nix` stays valid; add a check that inventory hosts ==
  `builtins.attrNames config.flake.nixosConfigurations`.
- `hosts/<h>/*.nix` leaf files (desktop.nix, hardware-configuration.nix) can stay plain path
  imports inside `nixosSystem.modules` — keeps the diff small.
- Migration order (zephyr first) works: keep classic `nixosConfigurations` for the other 3 hosts
  via a shim module using `common-modules-list.nix`; both styles merge fine.

**Unblocks:** convention-module-skeleton, convention-host-wiring, dissolve-modules-default,
inputs-specialargs-plumbing.
