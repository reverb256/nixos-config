---
type: research
assignee: resolved
blocked-by: []
labels: [wayfinder:research]
status: closed
---

## Question

Confirm the **eval-time tests + assertions** in this repo still resolve after the flake-parts
conversion. (Full question in the map's ticket.)

## Resolution

**CLOSED — research complete.** Findings:

- **No test evaluates `flake.nixosConfigurations.<host>`** — all 18 under `tests/` (17 wired into
  `checks.x86_64-linux` via `mkCheck`) are source-text / path-existence tests (`readFile`,
  `pathExists`, `hasInfix`).
- **8 of 18 break** on the dendritic migration, for two reasons:
  - `readFile`/`pathExists` on `hosts/<h>/{configuration,hardware-configuration,services}.nix`
    (host files move under `modules/hosts/<h>/default.nix`) → **eval throw**, not a false check.
  - grep for literal strings in `flake.nix` / `modules/default.nix` that `mkFlake` dissolves
    (e.g. `layer-interface-contract` hard-codes `hostInventory = import ./contracts/host-inventory.nix`
    and `nixosConfigurations`/`colmena`/`checks` literals).
- **Safe:** `k3s-cluster`, `firewall-lint` (if subdir names persist), `network-constants`,
  `secrets-integrity`, `k8s-manifest-validation`, `options-consistency`, `home-manager-layer`,
  `lib.nix`, `integration-smoke` (if module paths unchanged).
- `flake.nixosConfigurations.<host>` IS present and evaluable identically under `mkFlake` —
  `nixos-rebuild --flake .#zephyr` and colmena unaffected. `nix flake check` moves checks to
  `perSystem = { pkgs, ... }: { checks = {…}; }`.
- **⚠️ Real bug caught (pre-existing, fixed):** zephyr's k3s guard was declared
  `services.services.k3s-cluster.enable = lib.mkForce false` (nested one level too deep, inside
  the `services = {…}` block) — a no-op. Fixed to `k3s-cluster.enable = lib.mkForce false`.
  This is exactly the class of bug that migrating the topology test to real eval would catch.

**Recommended sequencing:** migrate `k3s-topology-evidence` to real eval
(`self.nixosConfigurations.<h>.config.services.k3s-cluster.{enable,role,nodeIP}`) BEFORE the
dendritic move — converts the zephyr guard from string-coincidence to a real check and catches
the nesting-typo class.

Full per-test map: see subagent report at
`/home/j_kro/.hermes/cache/delegation/subagent-summary-0-20260804_013348_506558.txt`.

**Next dependency:** convention-host-wiring / dissolve-modules-default should read the
per-test map before finalizing the host-layout decision (it constrains what paths survive).
