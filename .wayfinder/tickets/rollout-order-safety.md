---
type: convention
assignee: j_kro-agent (resolved)
blocked-by: [prototype-reference-conversion, research-online-verification]
labels: [wayfinder:rollout, wayfinder:safety]
status: closed
---

## Question

Determine the safe cutover sequence for the 4 live hosts (zephyr/nixos-free, nexus/builder,
forge/miners+revenue, sentry/k3s control-plane) converting to dendritic flake-parts, plus
the per-host verification gate, rollback net, and shim lifecycle — so 4 live nodes never
go down together.

## Resolution (grilled, 4 choices locked)

### Cutover ORDER
**zephyr → nexus → forge → sentry**

- **zephyr** — k3s-FREE guinea pig. No cluster dependency; if the dendritic pattern is
  wrong, only the desktop host is affected, nothing else breaks. (k3s guard already
  applied to its config: `services.k3s-cluster.enable = lib.mkForce false`.)
- **nexus** — builder host, migrated 2nd for EARLY STABILIZATION. Risk: nexus is the
  build host; during its cutover, cluster builds depend on zephyr being a viable fallback
  OR we accept a brief build-host-down window. Mitigation: zephyr must be able to build
  (it has nix + the flake); if a distributed build is needed from nexus, run it BEFORE
  nexus's cutover, or stage closures on zephyr. **The full verification gate (Q2) must
  include `nix build` of a representative closure on nexus post-cutover to confirm the
  builder still builds.**
- **forge** — miners / revenue-critical. Migrated 3rd ONLY after nexus proves the builder
  still produces valid closures (so a rollback rebuild is possible). Feature assertion:
  **miners must be hashing** post-cutover.
- **sentry** — k3s control-plane / inference. Migrated LAST. It is the cluster brain;
  validate the k3s path on a cheaper failure domain after forge's miners are proven safe.
  Feature assertion: **k3s nodes Ready**, inference endpoint responsive.

### Per-host VERIFICATION GATE (Q2 → Full gate, locked)
A host is "cutover done" ONLY when ALL of:
1. `nix flake check --all-systems` passes (all flake outputs, all 4 hosts' configs eval)
2. `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` succeeds (builds)
3. Deploy: `colmena apply --on <host>` (or local `nixos-rebuild switch` for zephyr)
4. Post-deploy smoke: `colmena exec <host> -- systemctl is-system-running` = `running`
   (or `degraded` with only known-benign units; NOT `failed`)
5. Feature assertions:
   - zephyr: desktop session reachable, `k3s` service NOT active (guard holds)
   - nexus: a representative `nix build` closure succeeds on the builder
   - forge: miners hashing (`peakminer`/auth-translator proxies reporting; GPU busy)
   - sentry: `kubectl get nodes` all Ready; inference endpoint 200

**Next host proceeds ONLY after the previous host is fully green. No batching.**

### ROLLBACK NET (Q3 → per-host generation rollback, locked)
- Every host retains its pre-cutover generation (NixOS keeps generations; GC keep window
  stays generous during migration).
- On a failed feature-assertion gate:
  `colmena exec <host> -- nixos-rebuild switch --rollback` (or boot to previous via
  console for a wedged host).
- **Cutover commits are ISOLATED PER-HOST** — one commit per host turning its
  `nixosConfigurations.<host>` dendritic + removing it from the classic shim list. A bad
  host's revert is a targeted revert/revert-commit; it does NOT touch the other 3 hosts'
  config or the still-classic shim. This is why dissolve is "after all 4" (Q4), not
  per-host.

### SHIM LIFECYCLE (Q4 → dissolve after all 4, locked)
- `common-modules-list.nix` + classic `mkNixosSystem` colmena path stay as the shim for
  the still-classic hosts throughout migration.
- **Dissolve ONLY after all 4 hosts are dendritic:**
  1. Flip colmena to `flake.colmena = ...; colmenaHive = colmena.lib.makeHive self.colmena`
     reading `flake.modules.nixos.*` + `flake.nixosConfigurations.*` (colmena#60 pattern).
  2. Delete `common-modules-list.nix`.
  3. `modules/default.nix` becomes the flake-parts aggregator (dissolve Q1=B): a path-list
     imported ONCE by flake.nix; NOT deleted — it is now the canonical registry.
- This is a SEPARATE ticket (`execute-zephyr-cutover` handoff or a follow-up), lands after
  the 4th host is green, not during.

## Relationship to other tickets
- Uses the verified template from `prototype-reference-conversion` (B: `flake.modules.nixos.*`).
- Sequencing overrides any "migrate all at once" instinct — incremental is the safety model.
- The `flake-input-consistency` test (eval-tests ticket) must be updated at dissolve time
  (it currently checks `common-modules-list.nix` contents).

## Note
zephyr currently rides an UNCOMMITTED/UNDEPLOYED branch (`wayfinder/prototype-dendritic`)
with the k3s guard + deleted `gaming-mining-coordinator.nix`. That IS the first cutover
commit candidate — but per the Standing Rule (no commit/deploy without say-so), it ships
only when `execute-zephyr-cutover` is green-lit.
