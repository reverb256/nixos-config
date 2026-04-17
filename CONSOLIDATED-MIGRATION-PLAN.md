# Consolidated Migration Plan

**Date:** 2026-04-17
**Goal:** Migrate all feasible workloads from systemd/zephyr to K8s/nexus using nix-csi + easykubenix

---

## Two Axes of Migration

### Axis 1: Systemd → Kubernetes (using nix-csi scratch pattern)
Converts systemd services to K8s Deployments/StatefulSets using:
- `ghcr.io/lillecarl/nix-csi/scratch:1.0.1` base image
- HostPath mounts for `/nix/store` access
- easykubenix Nix modules

### Axis 2: Zephyr → Nexus (reduce Zephyr RAM pressure)
Move any non-GPU, non-desktop workloads from Zephyr (31GB, tight) to Nexus (46GB)

---

## Priority Matrix

### P0 - Zephyr RAM Critical (Do Now)

| Service | Zephyr Current | Target | Method | RAM Saved |
|---------|---------------|--------|--------|-----------|
| redis-ai-gateway | systemd port 6380 | DELETE (Valkey in K8s search ns) | disable svc | ~50MB |
| caddy (local) | systemd | → K8s infra namespace | easykubenix | ~100MB |
| vaultwarden | systemd/podman | → K8s on nexus | easykubenix | ~100MB |

### P1 - Systemd → K8s Conversions

| Service | Host | Current | Target | Module |
|---------|------|---------|--------|--------|
| redis | zephyr | systemd | → K8s infra | host-services.nix |
| node-exporter | all 4 | systemd | → K8s DaemonSet | host-services.nix |
| nvidia-gpu-exporter | zephyr/nexus/forge | systemd | → K8s DaemonSet | host-services.nix |
| kb-mcp-server | nexus | systemd | DELETE (kf replaces) | — |
| qdrant | nexus | systemd | → K8s search ns | host-services.nix |
| knowledge-fabric | NEW | — | → K8s search ns | other agent |

### P2 - Zephyr → Nexus Moves

| Service | Zephyr Current | Nexus Target | Notes |
|---------|---------------|-------------|-------|
| ai-inference gateway | systemd :8080 | already there | gateway enable=false on zephyr |
| hermes-agent | systemd | → K8s | needs workspace PVC |
| hermes-dashboard | systemd | → K8s | simple web app |
| claude-code-router | systemd :3456 | → K8s | easykubenix defined |
| syncthing | systemd | keep systemd | host filesystem |

### P3 - Keep on Zephyr (Hardware/TDesktop Bound)

- k3s-cluster (control plane)
- keepalived-vip
- gaming-detection, gpu-profile-manager
- mining (lolminer, xmrig)
- desktop (lm-studio, haven-desktop)
- nixos-share server
- podman

---

## Implementation Order

```
Phase 1: Quick Zephyr Relief (P0)
├── 1.1 Delete redis-ai-gateway (zephyr + nexus)
├── 1.2 Deploy vaultwarden → K8s nexus
└── 1.3 Deploy caddy-local → K8s infra namespace

Phase 2: Systemd → K8s (P1)
├── 2.1 Deploy node-exporter DaemonSet
├── 2.2 Deploy nvidia-gpu-exporter DaemonSet  
├── 2.3 Deploy redis StatefulSet (infra ns)
├── 2.4 Deploy qdrant (search ns)
└── 2.5 Delete kb-mcp-server (nexus)

Phase 3: Zephyr → Nexus (P2)
├── 3.1 Deploy hermes-agent → K8s nexus
├── 3.2 Deploy hermes-dashboard → K8s nexus
└── 3.3 Deploy claude-code-router → K8s nexus
```

---

## K8s Modules Already Defined

**File:** `kubernetes/modules/host-services.nix` (just added to default.nix)

Contains easykubenix definitions for:
- Redis (port 6379)
- Redis AI Gateway (port 6380)
- Node Exporter (DaemonSet)
- NVIDIA GPU Exporter (DaemonSet)
- Vaultwarden
- Claude Code Router
- AI Inference Monitor
- Gaming Detection
- Mining Coordinator
- Mining-Inference Coordinator
- lolminer-nvidia (zephyr)
- Caddy Local
- Syncthing

---

## Next Steps

1. **Commit host-services.nix** (already git added)
2. **Fix flake eval** - currently failing on host-services.nix
3. **Deploy via colmena** to activate K8s definitions
4. **Disable systemd services** after K8s verification