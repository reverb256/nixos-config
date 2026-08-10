# Kubernetes Documentation

> **Status:** Active subsystem navigation
> **Last Verified:** 2026-08-09
> **Owner:** Cluster operations

This directory mixes active reference material, implementation history, incident reports,
and plans. A file is not an operational runbook merely because it contains `kubectl`
commands. Check its metadata and source-of-truth statement before following it.

## Authority and deployment sources

- **Runtime truth:** the live Kubernetes API (`kubectl get nodes`, workloads, events,
and resource state).
- **Nix/Easykubenix source:** `kubernetes/` and its modules where those modules generate
the deployed object.
- **Raw YAML source:** `kubernetes-manifests/` only for workloads whose owning subsystem
explicitly identifies the manifest as authoritative.
- **Bootstrap/vendor/test material:** must not be treated as the production source.
- **Scheduling and host inventory:** `contracts/host-inventory.nix`,
`kubernetes/cluster.nix`, and the rules in `kubernetes-manifests/AGENTS.md`.

Prefer repository validation and guarded deployment recipes over ad-hoc production
`kubectl apply` commands. Never run destructive commands from an unverified document.

## Maintained entry points

| Need | Start here | Notes |
|---|---|---|
| Cluster/Kubernetes authority boundaries | [`../current-state.md`](../current-state.md) | Checked-in versus live truth |
| Manifest conventions and scheduling | [`../../kubernetes-manifests/AGENTS.md`](../../kubernetes-manifests/AGENTS.md) | Active subsystem policy |
| Security response | `security-runbook.md` | Legacy reference; verify commands first |
| Ingress architecture | `caddy-ingress-architecture.md` | Reference; verify routes against Nix/manifests |
| Storage mapping | `storage-class-mapping.md` | Reference; verify capacity and provisioners |
| Disaster recovery | `disaster-recovery-runbook.md` | Verify against current rescue/deployment flow |
| Historical incidents | `incidents/` and `docs/archive/` | Historical evidence only |

## Classification rule

Only documents with current `Status` and `Last Verified` metadata are eligible for the
maintained active set. The remaining files are retained as reference/history pending
individual verification. Do not refresh their dates without checking their commands,
claims, and source files.

## Validation

```bash
just docs-audit
just validate-k8s
kubectl get nodes -o wide
kubectl get pods -A
```

For workload changes, identify the source-of-truth file first, validate the generated
manifests, then use the guarded deployment workflow documented in `docs/ci-cd/README.md`.
