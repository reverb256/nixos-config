---
type: grilling
assignee: j_kro-agent (resolved)
blocked-by: [research-flake-parts-mechanics]
labels: [wayfinder:grilling]
status: closed
---

## Question

Define the **host wiring convention** for the dendritic pattern, given explicit (non-import-tree)
wiring because hosts are heterogeneous. (Full question in the map.)

## Resolution

**CLOSED — convention locked via grilling (HITL).** Per-host wiring for this repo:

```nix
# modules/hosts/zephyr/default.nix — two-layer
{ inputs, config, withSystem, ... }: {
  flake.nixosModules.zephyrConfig = { config, lib, pkgs, ... }: {
    # Identity FIRST (Q6): the anchor tests/colmena read.
    networking.hostName = "zephyr";
    # ... cluster role / IPs ...

    imports = [
      config.flake.nixosModules.base          # common defaults (Q4)
      config.flake.nixosModules.zephyrHardware # per-host hardware aggregate (Q4/Q5)
      # + shared feature modules this host wants
      # + host-private modules (./vfio.nix ./peakminer.nix ...)
    ];
    # ... remaining config body as a blob (Q2: C then B — seams split now, rest later)
  };
  flake.nixosConfigurations.zephyr = withSystem "x86_64-linux" ({ system, ... }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };   # two-phase: removed in cleanup pass
      modules = [ config.flake.nixosModules.zephyrConfig ];
    });
}
# modules/hosts/default.nix — host registry (Q7)
{ imports = [ ./zephyr ./nexus ./forge ./sentry ]; }
```

Decisions (Q1–Q7):
1. **Two-layer (B):** host file defines `nixosModules.<host>Config` (content) + 
   `flake.nixosConfigurations.<host>` (evaluates it via `withSystem`). Tests/colmena consume
   the config module directly; no nixosSystem spin-up to read config.
2. **Config body: C then B** — split obvious seams (peakminer, monitoring, desktop, NVIDIA)
   into feature files during migration; rest stays a verbatim blob, decomposed in the later
   cleanup pass (with flat-features reorg).
3. **Per-host differences (B):** >1 host uses it → shared feature file; exactly 1 host →
   `modules/hosts/<host>/<feature>.nix` host-private module. Host = composition of shared
   features + private modules.
4. **`base` + per-host `hardware` aggregate (C):** every host imports `nixosModules.base`
   (system-packages, users, networking, ssh, tailscale, ...) + `nixosModules.<host>Hardware`
   (hardware-configuration.nix + GPU/VM modules). Separates "what it is" from "what it runs".
5. **`hardware-configuration.nix` = plain path import (A)** inside the hardware aggregate —
   generated data, never edited, never given a key.
6. **Host identity at top of config module (A)** — `networking.hostName` + cluster role/IPs;
   the anchor tests/colmena assert on.
7. **Host registry = `modules/hosts/default.nix` aggregator (B)** — lists the 4 hosts, imported
   once by flake.nix as `./modules/hosts`. New host = one line in that file, not the root flake.

**Unblocks:** dissolve-modules-default (registry precedent: aggregator vs self-register; Q3
shared/private rule feeds feature placement), prototype-reference-conversion (host skeleton +
seam-split list + base/hardware aggregates).
