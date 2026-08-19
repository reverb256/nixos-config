# Architecture Decision Record Index

> **Status:** Canonical decision navigation
> **Last Verified:** 2026-08-16
> **Owner:** Cluster operations
> **Authority:** The detailed decision table remains in [`ACTION-ITEMS.md`](../ACTION-ITEMS.md#decision-log); this file routes readers to the rationale and source material.

This index records where architectural decisions are documented. It does not turn
historical reports or generated snapshots into current operating procedures.

## How to use this index

1. Read the linked source/configuration before changing the system.
2. Treat `ACTION-ITEMS.md` as the current decision table and reconcile open items
   with the live issue/PR state.
3. Treat dated audits, incidents, and completed plans as historical evidence unless
   their claims have been re-verified.
4. Record a new decision when a change is expensive to reverse or changes an
   authority boundary. Preserve superseded rationale.

## Current decision areas

| Area | Decision or rationale | Primary record/source |
|---|---|---|
| Documentation authority | Checked-in configuration, live runtime state, generated snapshots, and historical evidence have separate authority boundaries. | [`docs/current-state.md`](current-state.md), [`docs/meta/DOCUMENTATION-STRATEGY.md`](meta/DOCUMENTATION-STRATEGY.md) |
| Deployment workflow | Use the Nexus-dispatched, guarded deployment path rather than an unguarded direct Colmena apply. | [`docs/current-state.md`](current-state.md), [`docs/ci-cd/README.md`](ci-cd/README.md), `justfile` |
| Kubernetes source of truth | Prefer Nix/Easykubenix modules for generated objects; raw manifests must identify their ownership and lifecycle. | [`docs/kubernetes/README.md`](kubernetes/README.md), [`kubernetes-manifests/AGENTS.md`](../kubernetes-manifests/AGENTS.md) |
| Ingress | Caddy, VIP, DNS, TLS, and NodePort details are documented as a reference boundary and must be checked against current Nix and Kubernetes sources. | [`docs/kubernetes/caddy-ingress-architecture.md`](kubernetes/caddy-ingress-architecture.md), `modules/services/cluster-ca.nix`, `kubernetes/service-ports.nix` |
| Secrets | SecretSpec is the runtime resolution path while sops-nix remains a compatibility path during migration; plaintext secrets do not belong in documentation. | [`docs/current-state.md`](current-state.md), [`SOPS-NIX.md`](../SOPS-NIX.md), `secretspec.toml` |
| Resource placement | Nexus is the default workload/build target; Zephyr is protected from non-infrastructure workload pressure. | [`docs/kubernetes/zephyr-ram-protection-policy.md`](kubernetes/zephyr-ram-protection-policy.md), `modules/system/distributed-builds.nix`, `kubernetes/cluster.nix` |
| Security backlog | Open hardening work and recorded rationale stay in the consolidated action-item table. | [`ACTION-ITEMS.md`](../ACTION-ITEMS.md#decision-log) |
| Sops envelope format | After `sops updatekeys` (2026-08-16) rewrote all envelopes JSON→YAML, the registry defaults to `format="yaml"` + `key="data"`; do not restore `binary` without re-encrypting to JSON (blocked by YubiKey). | [`SOPS-NIX.md`](../SOPS-NIX.md), `modules/system/sops-secrets-registry.nix`, commit `389fc2697` |
| Host wiring | Dendritic flake-parts pattern (Variant B path-import); shared `lib/dendritic-host.nix` evaluator for `nixosConfigurations` + `colmena`; classic shim dissolved 2026-08-13. | [`../modules/hosts/`](../modules/hosts/), [`../lib/dendritic-host.nix`](../lib/dendritic-host.nix), [`../contracts/host-inventory.nix`](../contracts/host-inventory.nix), [`../AGENTS.md`](../AGENTS.md) |

## Historical and superseded decisions

Historical audits, incident reports, and migration plans remain preserved under
[`docs/archive/`](archive/). They explain what was true or proposed at a point in
time; they are not current procedures unless the current-state and source checks
say otherwise.

## New decisions (2026-08-19)

### Nixpkgs harmonization between nixos-config and home-manager-config

**Decision:** Pin both flakes to the same nixpkgs rev (`0ae2bc1419c3f345984c2629e72e7a631820fa4d`, Aug 18 2026).

**Rationale:** The nixos-config flake was pinned to `0954f7ee2f6b` (Jul 29) while home-manager-config floated on `nixos-unstable`. This caused noctalia beta.6 (nixos-config) vs beta.8 (home-manager-config) version drift, producing configs the older daemon couldn't parse.

**Impact:** Both layers now resolve identical packages. The 3-week nixpkgs bump (Jul 29 → Aug 18) will require a full NixOS deploy.

**Source:** `flake.nix` (rev pin), `home-manager-config/flake.nix` (rev pin).

### Winewayland HDR gaming (Genshin Impact)

**Decision:** Enable `PROTON_ENABLE_WAYLAND=1` + `PROTON_ENABLE_HDR=1` + `DXVK_HDR=1` + `WINE_FULLSCREEN_FSR=1` in the AAGL wrapper for HDR-capable hosts.

**Rationale:** Native Wayland HDR requires the Wine Wayland driver (not Xwayland). FSR upscaling improves performance on 4K TV from sub-4K game internal resolution.

**Impact:** Genshin/HSR launch via anime-game-launcher get HDR + FSR env vars automatically on zephyr (HDR host).

**Source:** `modules/desktop/aagl.nix` (wrapper env vars).

### Razer mouse kernel timeout storm

**Decision:** Fix `openrazer.enable` conflict (hardware.nix:91 false → true) to start the daemon alongside the kernel module.

**Rationale:** The kernel module (`razermouse`) was loaded without the openrazer-daemon running, causing command timeouts every 10s that flooded dmesg and destabilized the input subsystem.

**Impact:** No more kernel timeouts. Likely cause of the 05:10:56 Genshin crash.

**Source:** `hosts/zephyr/hardware.nix:91`.

### Niri window rules for winewayland

**Decision:** Add `{app-id = "steam_proton"; title = "..."}` matches to window rules for games that launch via Proton (winewayland mode sets app-id to `steam_proton`, not the game name).

**Rationale:** Old rules only matched `.*GenshinImpact.*` app-id which doesn't match winewayland launches. Adding title-based matches catches the actual app-id.

**Impact:** Games launched via winewayland now route correctly to the Samsung TV workspace.

**Source:** `home-manager-config/modules/niri-config.nix` (window rules).

