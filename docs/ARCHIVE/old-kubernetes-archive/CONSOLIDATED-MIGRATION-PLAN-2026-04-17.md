# Consolidated Migration Plan
**Date:** 2026-04-17 | **Updated:** 2026-04-24
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
| redis-ai-gateway | systemd port 6380 | DELETE (Valkey in K8s search ns) | disable svc | ~50MB | ⚠️ Dual-running: systemd active + K8s pod Pending PVC |
| caddy (local) | systemd | → K8s infra namespace | easykubenix | ~100MB |
| vaultwarden | systemd/podman | → K8s on nexus | easykubenix | ~100MB |

### P1 - Systemd → K8s Conversions
| Service | Host | Current | Target | Module | Notes |
|---------|------|---------|--------|--------|-------|
| redis | zephyr | systemd **INACTIVE** (migrated to K8s) | → K8s infra | host-services.nix | systemd unit disabled |
| node-exporter | all 4 | systemd | → K8s DaemonSet | host-services.nix | |
| nvidia-gpu-exporter | zephyr/nexus/forge | **NOT RUNNING** (systemd) | → K8s DaemonSet **DEPLOYED** | host-services.nix | ⚠️ DaemonSet deployed, systemd still absent on all GPU nodes |
| kb-mcp-server | nexus | systemd | DELETE (kf replaces) | — | |
| qdrant | nexus | systemd | → K8s search ns | **NEW MODULE NEEDED** | ⚠️ **No K8s module defined yet** - needs creation |
| knowledge-fabric | NEW | — | → K8s search ns | other agent | |

### P2 - Zephyr → Nexus Moves
| Service | Zephyr Current | Nexus Target | Notes |
|---------|---------------|-------------|-------|
| ai-inference gateway | systemd **INACTIVE** on zephyr :8080 | K8s gateway on nexus | gateway running on nexus but /v1/models returns EMPTY — NIM cloud routing lost |
| hermes-agent | systemd | → K8s | needs workspace PVC |
| hermes-dashboard | systemd | → K8s | simple web app |
| claude-code-router | systemd :3456 | → K8s | easykubenix defined |
| syncthing | systemd | keep systemd | host filesystem |

### P3 - Keep on Zephyr (Hardware/TDesktop Bound)
- k3s-cluster (control plane)
- keepalived-vip
- gaming-detection, gpu-profile-manager
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
├── 2.2 Deploy nvidia-gpu-exporter DaemonSet (FRESH - no existing service)
├── 2.3 Deploy redis StatefulSet (infra ns)
├── 2.4 Create qdrant K8s module + deploy (search ns)
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

**Missing Modules (need creation):**
- Qdrant (referenced in ai-inference.nix but no K8s module)

---

## Future Improvements

### Migrate hostPath → nix-csi CSI Ephemeral Volumes

**Current State:** K8s modules use `hostPath.path = "/nix"` pattern. The nix-csi CSI driver IS deployed:
- `nix.csi.store` driver registered on all 4 nodes
- `nixkube` DaemonSet running with CSI node driver registrar

**Upstream Best Practice (Lillecarl):**
Use CSI ephemeral volumes instead of hostPath for better isolation and reproducibility:

```nix
volumes.nix.csi = {
  driver = "nix.csi.store";
  volumeAttributes.${pkgs.system} = pkgs.myPackage;
};
```

**Benefits:**
- Per-pod Nix store isolation
- Automatic garbage collection when pod terminates
- No host filesystem pollution
- True reproducible builds

**Migration Path:**
1. Update `nixVolume` in host-services.nix to use CSI ephemeral volumes
2. Test on non-critical workloads first
3. Roll out to all nix-csi scratch deployments

---

## Recurring Issues Log

### wlx-overlay-s → wayvr Package Rename
**Issue:** The `wlx-overlay-s` package was renamed to `wayvr` in nixpkgs upstream. This fix keeps getting reverted by another agent.

**History (git log):**
- `dd1fbf86` - fix: wlx-overlay-s → wayvr (nixpkgs upstream rename)
- `c59ad7bf` - fix: wlx-overlay-s → wayvr + other agent host config updates  
- `dc5a23a6` - fix(gaming): restore wlx-overlay-s (was incorrectly changed to wayvr)
- `aab12a6b` - fix: replace wlx-overlay-s with wayvr (upstream nixpkgs rename)
- `28e0f606` - refactor(gaming): replace dead VR config with upstream WiVRn module

**Action:** When updating gaming.nix, use `wayvr` (not `wlx-overlay-s`). The upstream package name change is intentional and permanent.

---

## 2026-04-24 Audit Notes

- K8s gateway (nexus) running but /v1/models returns EMPTY — NIM cloud routing lost
- Forge GPU miner: 46 replicas, 45 OutOfcpu — pod explosion, needs replica cap
- 8 Pending PVCs across namespaces — no StorageClass binding
- Mining coordinator hardcoded to port 1235 (sentry) instead of 1237 (zephyr 3090)
- nix-mineral: enabled on forge only, disabled on zephyr (niri breakage)
- Many P0/P1 items still in systemd — migration slower than planned
- Verified state: See ~/brain/STATUS.md (2026-04-24 audit)

## Next Steps

1. **Commit host-services.nix** (already git added)
2. **Create qdrant K8s module** - no module exists in host-services.nix yet
3. **Deploy via colmena** to activate K8s definitions
4. **Deploy nvidia-gpu-exporter fresh** - no existing systemd service to migrate
5. **Disable systemd services** after K8s verification
