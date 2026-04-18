# Kubernetes Nix Modules - Agent Context

**Parent:** `../../AGENTS.md` | **Domain:** K8s Nix modules via easykubenix (14 .nix files)

## Overview
Nix-native Kubernetes resource definitions using the easykubenix library.
These generate K8s YAML manifests that land in `../kubernetes-manifests/`.
Do NOT confuse with `../modules/services/k3s-cluster.nix` (the K3s daemon config).

## Where To Look

| Task | Location |
|------|----------|
| AI inference workloads | `ai-inference.nix` |
| GPU mining pods | `gpu-miners.nix`, `mining.nix` |
| LLM serving | `llama-servers.nix` |
| Infrastructure (Calico, etc.) | `infrastructure.nix` |
| Ingress routing | `ingress.nix` |
| Host-level services | `host-services.nix` (1365 lines — largest K8s module) |
| Monitoring dashboards | `monitoring.nix`, `monitoring-dashboards.nix` |
| SearXNG search | `searxng.nix` |
| Haven desktop | `haven.nix` |
| Common helpers | `common.nix`, `nixkube.nix` |

## Large Files (modify carefully)
- `host-services.nix` (1365 lines) — all host-level K8s services
- `monitoring.nix` (1031 lines) — full monitoring stack
- `mining.nix` (871 lines) — mining deployments
- `gpu-miners.nix` (655 lines) — GPU miner configs
- `llama-servers.nix` (587 lines) — LLM serving

## Relationship to YAML Manifests
- `kubernetes/modules/*.nix` → Nix definitions (source of truth)
- `kubernetes-manifests/*.yaml` → Generated/applied YAML (some hand-written)
- Changes to Nix modules regenerate manifests; hand-written YAML in `kubernetes-manifests/` may need manual sync

## Anti-Patterns
- Don't add `nodeSelector: zephyr` — use `nodeName: nexus` for workloads (OOM prevention)
- Don't forget `resources.requests` and `resources.limits` on every pod
- Set `revisionHistoryLimit: 2` and `maxSurge: 0` on all Deployments
