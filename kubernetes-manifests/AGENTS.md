# Kubernetes Manifests - Agent Context

> **Status:** Active subsystem guidance
> **Last Verified:** 2026-08-09
> **Source:** `kubernetes-manifests/` is a mixed manifest/reference tree; each workload's source-of-truth is declared by its subsystem guidance.

**Parent:** `../AGENTS.md` | **Domain:** K8s deployment configs (approximate file/directory counts; inventory is not live evidence)

## Overview
Kubernetes YAML manifests for cluster workloads. Organized by application domain.
Uses **Flannel CNI** (VXLAN, UDP 8472). Calico configs in `calico/` are archived reference material only.
K8s Nix modules live in `../kubernetes/modules/` (Easykubenix, 21 `.nix` files) and are the source of truth where they generate the deployed workload. Raw YAML in this tree is authoritative only where the owning subsystem explicitly says so; otherwise it is bootstrap, test, vendor, or archived reference.

## Structure
```
kubernetes-manifests/
├── mining/              # GPU mining manifests
├── ai-inference/        # AI workload manifests
├── ai-coding-tools/     # Development tool manifests
├── monitoring/          # Prometheus/Grafana manifests
├── calico/              # Archived Calico CNI reference configs (not active)
├── ingress/             # Ingress controllers (16 files)
├── spacebot/            # Discord bot (14 files)
├── pod-disruption-budgets/  # PDBs (18 files)
├── security/            # Admission policies (deny-latest-tag, etc.)
└── archive/             # Deprecated manifests
```

## Where To Look

| Task | Location |
|------|----------|
| Deploy AI workload | `ai-inference/` |
| Configure mining | `mining/` |
| Set up monitoring | `monitoring/` |
| View archived CNI configs | `calico/` |
| Add ingress rule | `ingress/` |
| Block :latest tags | `security/deny-latest-tag.yaml` |

## Anti-Patterns (THIS DIRECTORY)

| Pattern | Why | Fix |
|---------|-----|-----|
| Missing resource limits | Unbounded pods | Add `resources.requests/limits` |
| No PDB for critical services | Downtime risk | Create PDB in `pod-disruption-budgets/` |
| Using `:latest` tags | Blocked by admission policy | Pin to specific version |
| `maxSurge: 1` (default) | Pod explosion during updates | Set `maxSurge: 0` |
| `revisionHistoryLimit: 10` (default) | Replica set accumulation | Set to `2` |

## Node Scheduling Rules

| Node | RAM | Workloads |
|------|-----|-----------|
| **nexus** | Checked-in inventory: 46GB | DEFAULT workload target |
| **zephyr** | Checked-in inventory: 31GB | Infrastructure + mining policy |
| **forge** | Checked-in inventory: 15GB | Mining + GPU compute policy |
| **sentry** | Checked-in inventory: 31GB | Monitoring + Vulkan AI policy |

These are planning values from the repository inventory; verify live allocatable resources
with `kubectl top nodes` and `kubectl describe node` before scheduling changes.

### Scheduling Pattern
```yaml
# Preferred: nodeAffinity
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values: [nexus]

# Simple: nodeName
spec:
  template:
    spec:
      nodeName: nexus
```

## Namespace Convention
- `ai-inference` → AI workloads
- `monitoring` → Prometheus stack
- `mining` → GPU miners
- `calico-system` → Archived Calico configs (not active, Flannel is the CNI)

## Secret References

The source-of-truth boundary is also documented in [`docs/current-state.md`](../docs/current-state.md).

- SecretSpec is the runtime resolution path; sops-nix remains a compatibility path during migration.
- Encrypted material is declared under `/etc/nixos/secrets/` and `secretspec.toml`.
- Never add plaintext values to manifests or documentation. K8s workloads should consume
  runtime-materialized secrets through the owning Nix/SecretSpec wiring.
