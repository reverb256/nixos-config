# Incus and Cluster Reliability Hardening Design

Date: 2026-08-10
Status: approved for staged implementation

## Goal

Implement the highest-leverage recommendations from the Incus, deployment, SecretSpec, and hardware-provenance review without causing destructive live changes or claiming end-to-end completion before runtime evidence exists.

## Stage 1: Incus safety contract

The Zephyr Game Pass VM has one backend: Incus. Activation must configure prerequisites and declarative profiles, but must not create or start a VM.

The preseed path is fail-closed:

- a registered `gamepass` pool with the expected `dir` driver and `/var/lib/incus-gamepass` source passes without reinitialization;
- an absent pool with an empty/new managed source may be initialized;
- an orphaned or unexpected existing directory fails with a diagnostic and requires operator inventory/confirmation;
- no unconditional deletion, overwrite, or `|| true` around reconciliation.

The dynamic handoff only targets RTX 3060 Ti functions `0000:24:00.0` and `0000:24:00.1`. It validates PCI vendor/device identity, IOMMU-group assumptions, and expected current drivers before binding. The RTX 3090 is outside the handoff device set and must remain host-owned. Failed transitions restore the host-driver state where possible and leave an explicit error otherwise.

## Stage 2: Validation and canary deployment

Add deterministic source checks for the Incus-only backend, storage preservation, PCI identity contract, and reconciliation behavior. Evaluate the Zephyr system closure before deployment. Deploy Zephyr alone through the Nexus dispatcher only after checks pass. Confirm active-generation unit provenance and failed-unit state before any broader rollout. Never create/start the Windows VM automatically.

## Stage 3: Deployment reliability

Use the existing Nexus dispatcher as the exclusive executor. Strengthen canary execution with a single-deployment lock, origin/main checkout verification, machine-readable result/generation evidence, post-switch probes, and fail-stop rollback behavior. Test one host before fleet rollout.

## Stage 4: SecretSpec certification

After deployment reliability is stable, build the pinned SecretSpec components, run ephemeral-age local validation, verify generated per-host credential wiring and consumer usage, and remove legacy Path B assignments only after runtime evidence. Update issue/documentation status with deployed commit and host generations.

## Stage 5: Hardware and remaining cleanup

Add pre-deploy hardware provenance checks for host-specific boot/root/data/swap mappings. Verify live mappings before disk-layout work. Address ntfy package/schema compatibility separately. Make CI enforce evaluation, consistency, and relevant safety gates.

## Non-goals and safety boundaries

- Do not delete or automatically adopt `/var/lib/incus/storage-pools/gamepass`.
- Do not revive the retired libvirt backend.
- Do not bind the 3090 to VFIO.
- Do not start or create the Windows VM during NixOS activation.
- Do not deploy all hosts until the Zephyr canary and health evidence are successful.
