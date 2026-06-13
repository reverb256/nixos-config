# Systemd → K8s Migration Execution Plan
## Generated: 2026-04-17

## Phase 0: Immediate Zephyr RAM Relief (Do First)

### 1. diskann-valkey → Already Migrated ✅
- Valkey running in K8s `search` namespace
- Action: Delete systemd `redis-ai-gateway` on zephyr

### 2. prometheus-node-exporter DaemonSet
**Source:** `modules/services/node-exporter.nix`
**Target:** K8s DaemonSet in `monitoring` namespace
**Nodes:** all 4
**HostPath:** `/proc`, `/sys`, `/`
**Priority:** P0

### 3. vaultwarden → K8s
**Source:** `hosts/zephyr/services.nix` (podman)
**Target:** `kubernetes-manifests/vaultwarden/`
**Node:** nexus (46GB RAM)
**Storage:** PVC for `/data`
**Priority:** P0

---

## Phase 1: P1 Critical Services

### 4. nvidia-gpu-exporter DaemonSet
**Source:** New (no existing systemd)
**Target:** K8s DaemonSet on GPU nodes (zephyr, nexus, forge, sentry)
**HostPath:** `/run/nvidia` for NVML
**Priority:** P1

### 5. claude-code-router → K8s
**Source:** `hosts/zephyr/services.nix`
**Target:** `kubernetes-manifests/claude/`
**Node:** nexus
**Port:** 3456
**Priority:** P1

### 6. syncthing → Decision
**Evaluation:** Host filesystem heavy, needs bidirectional sync
**Recommendation:** KEEP systemd (hard to do properly in K8s)
**Priority:** P2

---

## Phase 2: P2-P3 Services (After P0/P1 Stable)

### 7. hermes-agent → K8s
**Source:** `hosts/nexus/services.nix`
**Target:** `kubernetes-manifests/hermes/`
**Node:** nexus
**Needs:** Workspace PVC for ~/.hermes

### 8. hermes-dashboard → K8s
**Source:** `hosts/nexus/services.nix`
**Target:** Same namespace as hermes-agent

### 9. llamafile → Decision
**Blocker:** GPU + model files on host
**Options:** 
  - Keep systemd (recommended)
  - Complex: Init container to sync models, hostPath for /nix/store

### 10. lm-studio-headless → Decision
**Blocker:** GPU, models, GUI settings
**Recommendation:** Keep systemd (desktop/GPU bound)

---

## Execution Order
1. ✅ diskann-valkey (delete zephyr systemd)
2. 📍 prometheus-node-exporter DaemonSet
3. 📍 vaultwarden Deployment
4. 📍 nvidia-gpu-exporter DaemonSet
5. 📍 claude-code-router Deployment
6. Evaluate hermes-* migration

---

## Definition of Done Per Service
1. K8s manifest written in `kubernetes-manifests/<service>/`
2. Deployed with `kubectl apply -k`
3. Pod running (`kubectl get pods`)
4. Service accessible (curl / port-forward test)
5. systemd service stopped (`systemctl stop`)
6. NixOS config disabled (service removed from host config)
7. Colmena deployed
