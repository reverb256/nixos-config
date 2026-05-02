# Kubernetes Manifests - Agent Context

**Parent:** `../AGENTS.md` | **Domain:** K8s deployment configs (~256 files, ~28 dirs)

## Overview
Kubernetes YAML manifests for cluster workloads. Organized by application domain.
Uses **Flannel CNI** (VXLAN, UDP 8472). Calico configs in `calico/` are archived reference material only.
K8s Nix modules live in `../kubernetes/modules/` (easykubenix, 21 .nix files).

## Structure
```
kubernetes-manifests/
├── mining/              # GPU mining (34 files)
├── ai-inference/        # AI workloads (22 files)
├── ai-coding-tools/     # Development tools (22 files)
├── monitoring/          # Prometheus/Grafana (16 files)
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
| **nexus** | 46GB | DEFAULT for all workloads |
| **zephyr** | 31GB | Infrastructure + mining ONLY |
| **forge** | 16GB | Mining + GPU compute |
| **sentry** | 31GB | Monitoring + Vulkan AI inference |

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
- Agenix-encrypted secrets in `/etc/nixos/secrets/` (42 .age files)
- K8s secrets reference same values via env vars
