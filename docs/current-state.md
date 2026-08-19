# NixOS Cluster Current State

> **Status:** Active reference
> **Last Verified:** 2026-08-13 (repository structure and checked-in configuration)
> **Owner:** j_kro
> **Live-state rule:** This document describes the checked-in architecture. Verify host health and deployed generations with the commands below before making claims about runtime state.

## Purpose

This is the short, current-state reference for humans and agents. It separates checked-in
configuration from live cluster observations so stale generated snapshots and historical
audits are not mistaken for the current deployment.

- **Configuration truth:** the checked-out Git revision in `/etc/nixos` and the
  `home-manager-config` flake input.
- **Deployment truth:** the active NixOS generation and service state on each host.
- **Kubernetes truth:** the live API server for runtime state; the applicable
  Nix/Easykubenix source, raw/bootstrap manifest, Helm chart, or operator configuration
  for the corresponding deployment source.
- **Historical truth:** dated incident reports, audits, migration plans, and research in
  the archive or explicitly dated documents. Historical documents are not procedures
  unless re-verified.

## Repository and workflow

This repository is the Layer 1 NixOS configuration for a four-host cluster. User
configuration is Layer 2 in the separate `home-manager-config` repository; high-churn
user tools are Layer 3 in the user Nix profile.

Normal workflow:

```text
issue → dedicated worktree → change → parse/check/test → PR → merge to main
→ Nexus-dispatched canary/deploy → provenance and health verification
```

Operational commands are defined in `justfile`. In particular:

```bash
just status          # local Git/worktree overview
just check           # flake evaluation/checks
just health          # SSH reachability and Kubernetes node summary
just provenance      # deployed generation/commit/drift evidence
just deploy-canary   # rolling deployment with post-switch probes
just deploy-async    # disconnect-safe Nexus dispatch
just docs-audit      # documentation verification suite
```

Zephyr is the authoring/source-of-truth host and should not perform heavy local Nix
builds. Nexus is the deployment dispatcher and primary builder. Use the Nexus dispatcher
rather than an unguarded direct Colmena apply.

## Hosts

| Host | Primary role | Checked-in identity |
|---|---|---|
| **Zephyr** | workstation, control plane, gaming, desktop/Niri, local cluster authority | `hosts/zephyr/`, shared modules under `modules/` |
| **Nexus** | primary builder/dispatcher, storage, ingress, AI services | `hosts/nexus/`, shared modules under `modules/` |
| **Forge** | GPU compute and mining | `hosts/forge/`, shared modules under `modules/` |
| **Sentry** | monitoring, logging, AMD/Vulkan inference and recovery target | `hosts/sentry/`, shared modules under `modules/` |

Host addresses, roles, scheduling facts, and deployment metadata are defined in
[`contracts/host-inventory.nix`](../contracts/host-inventory.nix) and
[`kubernetes/cluster.nix`](../kubernetes/cluster.nix). These are checked-in inventory
facts, not live hardware discovery. Do not treat an address in an old report as
authoritative.

## Configuration boundaries

- **NixOS:** `/etc/nixos`, including `hosts/`, `modules/`, `kubernetes/`, `packages/`,
  `pkgs/`, `scripts/`, and contracts.
- **Home Manager:** `/home/j_kro/Projects/home-manager-config`, consumed through the
  `home-manager-config` flake input. Niri user configuration and keybinds live there.
- **Secrets:** SecretSpec is the runtime resolution path; sops-nix remains a compatibility
  path until the planned Phase 3 removal. Never put plaintext secrets in documentation.
- **PKI and SSH:** the checked-in CA certificate is the fleet trust anchor; private
  signing keys are provisioned at runtime. SSH host trust is CA-based where configured.
- **Kubernetes:** prefer Nix/Easykubenix modules and the typed service/host contracts.
  Raw manifests must identify whether they are live, bootstrap-only, test, generated,
  vendor, or archived.
- **Persistence/recovery:** persistent hosts use the checked-in Preservation modules;
  recovery and rescue procedures must be tested against the current boot/storage layout.

## Documentation routing

| Need | Read first | Authority boundary |
|---|---|---|
| Safety rules and agent behavior | [`AGENTS.md`](../AGENTS.md) | Canonical policy |
| Contribution/worktree/PR workflow | [`CONTRIBUTING.md`](../CONTRIBUTING.md) | Canonical workflow |
| Repository navigation | [`../DOCUMENTATION_INDEX.md`](../DOCUMENTATION_INDEX.md) | Canonical catalog |
| Current checked-in architecture | This document | Current reference |
| Live host/Kubernetes health | `just health`, `just status`, `just provenance` | Runtime state, not prose |
| Deployment procedure | `justfile`, `docs/ci-cd/README.md`, verified rescue/deploy runbooks | Commands must match source |
| Secrets architecture | [`../SOPS-NIX.md`](../SOPS-NIX.md), `secretspec.toml`, and host SecretSpec wiring | Verify before rotation |
| Open remediation backlog | [`../ACTION-ITEMS.md`](../ACTION-ITEMS.md), GitHub issues/PRs | Reconcile dates/status |
| Historical audit or incident | Dated audit/incident document | Historical only unless re-verified |
| Archived material | `docs/archive/` | Historical material is preserved under `docs/archive/legacy/`; do not follow blindly |

## Verification commands

Run these before claiming that the cluster is healthy or that a deployment is complete:

```bash
just status
just health
just provenance
kubectl get nodes -o wide
kubectl get pods -A
```

For a configuration-only claim:

```bash
nix flake check
nix-instantiate --parse hosts/<host>/configuration.nix
```

For a Niri configuration claim, validate with the compositor package selected for the
host rather than an unrelated system binary. For a deployment claim, record the commit,
flake lock state, active generation, and health-probe result.

## Freshness and history

- Active/reference documents require `Status`, `Last Verified`, and an owner or source.
- Generated documents must name their generator and source-of-truth file; their timestamp
  is not proof that the underlying cluster was reachable.
- Historical documents retain their original dates and must be marked historical or
  archived. Do not silently rewrite incident timelines.
- `STATUS.md` is a generated snapshot and may be stale; do not use it as a substitute for
  live commands until its snapshot timestamp and generator result are checked.
- `ROADMAP.md` is migration/roadmap history plus remaining hardening context, not a live
  health dashboard.
- The 2026-07-27 multi-area audit is the latest broad audit currently indexed, but its
  findings still require live verification before operator action.

## 2026-08-13 cluster state changes

Session-verified changes (commits on `origin/main`):

- **nix-csi removed entirely** (`ad405b34`) — driver never registered (csinode lacked
  `nix.csi.store`), build inputs GC'd from all stores, no production consumers. 6 manifests
  moved to `kubernetes-manifests/archive/nix-csi/`; live DS/STS/jobs/SC/CSIDriver deleted.
  Closes #213. #191/#205 superseded.
- **nvidia-device-plugin fixed** (`7119ff89`, `88606d98`) — nodeSelector aligned to real
  k3s label (`accelerator=nvidia-gpu`), driver lib path refreshed (had GC'd 595.45.04),
  NVML lib dir corrected (610.43.03 main lib, not lib32). `nvidia.com/gpu: 1` advertised
  on nexus. GPU workloads schedulable again.
- **k8s-secret-sync namespace-ensure** (`cac6b4e4`) — unit now creates target namespaces
  (`automation`, `orchestration`) before syncing; unblocked nexus deploys (was exit 4).
- **nixos-sync openssh in PATH** (`5dbd999f`) — git fetch over SSH needed `pkgs.openssh`;
  also `HOME=/root` env + FLAKE ordering (documented in `modules/services/nixos-sync.nix`).
- **dcgm RuntimeDirectory** (`9d53c2ce`) — podman cidfile dir exists at start.
- **bonsai sentry DSpark removal** (`e91d8133`) — mainline Vulkan cannot load `dspark` arch.

Open follow-ups filed 2026-08-13: #463 qdrant admission-policy block, #464 gateway
placeholder keys, #465 orphaned HPAs, #466 maplespike secrets re-wiring (cross-linked
with quill PR #826).

## 2026-08-13 PR merge session

Merged to `origin/main` (all sibling PRs reviewed, eval-verified):

- **#457** nixos-sync non-destructive (`merge --ff-only`, skip dirty/non-main trees,
  per-command safe.directory) — supersedes the earlier hard-reset approach.
- **#459** zephyr cgroups (issue #453) — `use-cgroups`, idle daemon CPU/IO scheduling.
- **#460** CI Layer-2 lock guard — deploy aborts if home-manager-config flake.lock is
  behind master.
- **#461** ai-inference parse coverage — restored `}` in kubernetes/modules/ai-inference.nix.
- **#462** nim-proxy concurrency — ThreadingHTTPServer + BoundedSemaphore (issue #313).
- **#467** portable pure-eval (#309) — cherry-picked from auto-closed #458 (GitHub closed
  it during the #457 merge race; content identical, 4 files: cache.yml timeout guard,
  portable-usb modelAvailable gate, flake.nix check, new test).
- **flake.lock** bumped to home-manager-config `af29c5037` (Alt+Tab + KDE/MIME fix) —
  keeps the #460 guard green.

Not merged (coordination): **quill PR reverb256/maplespike#826** — sibling agent has
in-flight dev-mode work on the same files (nix/saas-manifests.nix, AGENTS.md). Merging
now would force their rebase; land it after their dev-mode namespace work commits.

See [`../DOCS-MAINTENANCE.md`](../DOCS-MAINTENANCE.md) for the classification and
freshness policy. The documentation cleanup manifest records completed and planned
migration batches without rewriting historical evidence.

## 2026-08-19 cluster state changes

- **TPM 2.0 age-key binding** — `modules/system/tpm2-age-binding.nix` adds hardware
  binding for the SecretSpec/sops identity key. All 4 hosts (zephyr, nexus, forge,
  sentry) have `/dev/tpmrm0` (TPM 2.0). The module seals the host's age key to PCRs
  0+7 via `tpm2-seal-age-keygen.service` (one-time) and unseals it to
  `/run/secrets/cluster-age-key` at boot via `tpm2-unseal-age.service`.
  `services.secretspec-creds.ageKeyFile` is overridden with `mkForce` to the
  runtime path. This sits *below* SecretSpec — no changes to secretspec itself.
  See [SOPS-NIX.md](../SOPS-NIX.md) §"TPM 2.0 hardware-binding" and
  `docs/reference/known-issues.md`.

## Secrets architecture (updated)

The secrets layer now has two hardware-backed mechanisms:

| Mechanism | Scope | Key purpose | Status |
|---|---|---|---|
| **YubiKey (PIV/GPG)** | Host authentication + manual age decryption | Login (PAM U2F), sudo, SSH CA signing, GPG smartcard | Production |
| **TPM 2.0 (PCR 0+7)** | SecretSpec/sops activation-time age key | Unattended boot-time unseal of the cluster age key | New (2026-08-19) |

YubiKeys remain enrolled as additional `.sops.yaml` recipients for **manual**
CLI/keyservice decryption. TPM sealing is complementary — it handles the
unattended activation path where SecretSpec resolves 58 `sops://` secrets and
feeds them to secretspec-creds systemd units.
