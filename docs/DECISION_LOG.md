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
| TPM 2.0 age-key binding | The static cluster age key (SecretSpec/sops identity) is auto-sealed to TPM 2.0 PCRs 0+7 on first boot (zero manual steps), unsealed into `/run/secrets/cluster-age-key` at every boot, and consumed via the existing `SOPS_AGE_KEY_FILE` env var. Does NOT modify SecretSpec — sits below it as a key-provisioning layer. Complements, not replaces, YubiKey age recipients. All 4 hosts have TPM 2.0; all 4 currently have Secure Boot disabled (PCR 7 reflects "SB off" state). | [`../docs/reference/known-issues.md`](../docs/reference/known-issues.md), [`../modules/system/tpm2-age-binding.nix`](../modules/system/tpm2-age-binding.nix), [`../SOPS-NIX.md`](../SOPS-NIX.md#TPM-2.0-hardware-binding) |
| Sops envelope format | After `sops updatekeys` (2026-08-16) rewrote all envelopes JSON→YAML, the registry defaults to `format="yaml"` + `key="data"`; do not restore `binary` without re-encrypting to JSON (blocked by YubiKey). | [`SOPS-NIX.md`](../SOPS-NIX.md), `modules/system/sops-secrets-registry.nix`, commit `389fc2697` |
| Host wiring | Dendritic flake-parts pattern (Variant B path-import); shared `lib/dendritic-host.nix` evaluator for `nixosConfigurations` + `colmena`; classic shim dissolved 2026-08-13. | [`../modules/hosts/`](../modules/hosts/), [`../lib/dendritic-host.nix`](../lib/dendritic-host.nix), [`../contracts/host-inventory.nix`](../contracts/host-inventory.nix), [`../AGENTS.md`](../AGENTS.md) |

## Historical and superseded decisions

Historical audits, incident reports, and migration plans remain preserved under
[`docs/archive/`](archive/). They explain what was true or proposed at a point in
time; they are not current procedures unless the current-state and source checks
say otherwise.
