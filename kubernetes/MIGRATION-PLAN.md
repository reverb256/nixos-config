# K8s Migration Plan — systemd → easykubenix

**Created:** 2026-04-14 | **Status:** Phase 1.7+ — K3s running 19+ days, multiple services migrated, audit completed 2026-04-24

## Current State

### Already in easykubenix (native)

| Module | Resources | Status |
|---|---|---|
| `common.nix` | PriorityClasses | ✅ |
| `infrastructure.nix` | Namespaces, NetworkPolicy, PSS | ✅ |
| `gpu-miners.nix` | 6 lolMiner deployments (forge×4, zephyr, nexus) | ⚠️ nexus not deployed |
| `mining.nix` | xmrig (zephyr, nexus, sentry, proxy) | ✅ |
| `haven.nix` | haven deployment | ✅ running |
| `searxng.nix` | searxng (2 replicas) | ✅ |
| `host-services.nix` | Host service definitions | ✅ `nix flake check` passes all 4 hosts |

| `ai-inference-gateway` | K8s gateway deployment | ⚠️ deployed to nexus, returns empty /v1/models (NIM routing lost) |
### importyaml (needs conversion)

| Module | Source | Resources |
|---|---|---|
| `ai-inference.nix` | `ai-inference-clean.yaml` (13KB) | grafana ✅ running, open-webui ✅ running, ingresses, SAs, RBAC, 6 ConfigMaps |
| `nixkube.nix` | `nixkube-clean.yaml` (28KB) | nix-node DaemonSet, proxy, nix-cache StatefulSet, CMs |
| `ingress.nix` | `caddy-ingress-controller.yaml` (5KB) | caddy controller, SA, ClusterRole, ConfigMap |

> **Note:** These importyaml modules are partially migrated — some services from these imports are already running in the cluster.
### systemd services (candidates for migration)

| Service | Nodes | Type | K8s Pattern | Priority |
|---|---|---|---|---|
| `llamafile` | zephyr | GPU inference (CUDA) | Deployment + hostPath | P0 — INACTIVE systemd, running as K8s pod |
| `llama-server` | sentry | GPU inference (ROCm) | Deployment + hostPath | P0 — INACTIVE systemd, running as K8s pod |
| `prometheus-node-exporter` | all 4 | Host metrics | DaemonSet | P1 |
| `prometheus-mining-exporter` | nexus, forge, sentry | GPU metrics | DaemonSet + hostPath | P1 |
| `xmrig-proxy` | zephyr | Stratum proxy | Deployment | P1 |
| `ai-inference-gateway` | zephyr, sentry | API gateway | Deployment | P2 — INACTIVE on zephyr systemd, K8s gateway on nexus but broken (empty /v1/models) |
| `ai-inference-monitor` | zephyr, nexus, sentry | Health monitor | Deployment | P2 |
| `prometheus` | nexus, sentry | Metrics | StatefulSet + PVC | P2 |
| `alertmanager` | nexus, sentry | Alerting | StatefulSet | P2 |
| `loki` | sentry | Log aggregation | StatefulSet + PVC | P3 |
| `alert-webhook` | sentry | Alert relay | Deployment | P3 |
| `vaultwarden` | zephyr | Password manager (podman) | Deployment + PVC | P3 |
| `host-dashboard` | all 4 | Host info dashboard | DaemonSet | P3 |

> **Note:** `nvidia-gpu-exporter` systemd service is inactive on all hosts — this is a fresh deployment, not a migration from an existing service.

### Stay systemd (hardware/desktop bound)

- display-manager, ckb-next, rgb-temperature-control, fail2ban
- gaming-detection, mining-coordinator (need host process visibility)
- keepalived (VIP failover), caddy (local proxy), claude-code-router
- gpu-proxy-cpp (GPU scheduling), syncthing (filesystem)
- redis, redis-ai-gateway, qdrant (stateful, low migration value) — **note:** redis and redis-ai-gateway now running as K8s pods in infra namespace, but systemd units may still be active on some hosts

> **Note:** qdrant needs a new K8s module definition (not currently in any easykubenix module).

---

## Phase 0: Cleanup (no migration, just hygiene)

- [ ] Delete orphan ConfigMaps in ai-inference namespace
- [ ] Decide on gpu-miner-nexus (deploy or remove definition)
- [ ] Add `app.kubernetes.io/managed-by: easykubenix` label to all native modules

## Phase 1: Convert importyaml → native easykubenix

- [ ] `ai-inference.nix` — convert grafana + open-webui to native, keep only active ConfigMaps
- [ ] `ingress.nix` — convert caddy controller to native
- [ ] `nixkube.nix` — convert DaemonSet + StatefulSet to native

## Phase 1.5: Decisions

- [x] `nixkube.nix` — keep as importyaml (1006 lines, CSI DaemonSet with 5 containers, low change frequency)
- [x] `llamafile`/`llama-server` — keep as systemd for now (Nix-built binaries auto-track store paths; K8s would need a custom Docker image per rebuild)
- [x] `wlx-overlay-s` renamed to `wayvr` in nixpkgs — `gaming.nix` updated to reflect this

## Phase 1.6: nix-csi CSI Driver Deployed

The nix-csi CSI driver is confirmed deployed and operational:

- **Driver:** `nix.csi.store` available on all 4 nodes
- **Namespace:** `nixkube` contains:
  - `nix-node` DaemonSet (CSI node plugin)
  - `nix-cache` StatefulSet (optional caching layer)
- **Current modules** use `hostPath /nix` as a transitional pattern, not the final architecture

## Phase 1.7: Migrate hostPath → nix-csi CSI volumes
> **Deferred:** hostPath → CSI migration is deferred; hostPath pattern is still in active use across multiple modules.

Convert the transitional hostPath pattern to the upstream-recommended CSI ephemeral volume pattern:

```nix
volumes.nix.csi = {
  driver = "nix.csi.store";
  volumeAttributes.${pkgs.system} = pkgs.myPackage;
};
```

**Benefits:**
- Shares inodes across pods on the same node (deduplication)
- More RAM-efficient than hostPath (single copy in memory)
- Native K8s lifecycle management (volume follows pod)
- Consistent with upstream nix-csi recommendations

**Migration Steps:**
1. Audit all modules using `hostPath /nix` mounts
2. Replace with `volumes.nix.csi` pattern
3. Verify pod startup and package availability
4. Remove hostPath volume definitions

---

## Phase 2: Migrate systemd → K8s (P1)

- [ ] `prometheus-node-exporter` (all) → K8s DaemonSet
- [ ] `prometheus-mining-exporter` (nexus/forge/sentry) → K8s DaemonSet
- [ ] `xmrig-proxy` (zephyr) → K8s Deployment

## Phase 3: Migrate systemd → K8s (P2-P3)

- [ ] `ai-inference-gateway` → K8s Deployment
- [ ] `ai-inference-monitor` → K8s Deployment
- [ ] `prometheus` + `alertmanager` → K8s StatefulSets
- [ ] `loki` → K8s StatefulSet + PVC
- [ ] `vaultwarden` → K8s Deployment + PVC
- [ ] `host-dashboard` → K8s DaemonSet

---

## Approach

Each migration follows the same pattern:

1. Read the systemd service config (ExecStart, Environment, volumes)
2. Write easykubenix native module with same config
3. Deploy to cluster
4. Verify pod running + service accessible
5. Disable the systemd service in NixOS config
6. Deploy NixOS to stop systemd service
7. Clean up old NixOS module code

## Risks

- **hostPath pods need privileged security context** — same pattern as gpu-miners
- **Nix store paths change per build** — must reference `pkgs.llama-cpp` not hardcoded store paths
- **Model files on host filesystem** — need hostPath mounts for `/home/j_kro/.lmstudio`
- **Sentry llama-cpp-rocm is stale** — must wait for deploy before migrating


## 2026-04-24 Audit Notes

- K8s gateway deployed to nexus but returns empty /v1/models — NIM routing lost
- Forge GPU miner pod explosion: 46 replicas, 45 OutOfcpu
- 8 Pending PVCs — no StorageClass binding
- Monitoring stack mostly operational: Alloy 4/4, Prometheus, Grafana, Loki running
- prometheus-adapter fixed (was CrashLoop, now Running)
- nix-mineral enabled on forge only, disabled on zephyr
- Many systemd services still dual-running with K8s pods
- Verified state: See ~/brain/STATUS.md (2026-04-24 audit)
