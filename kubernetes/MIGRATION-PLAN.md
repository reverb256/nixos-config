# K8s Migration Plan — systemd → easykubenix

**Created:** 2026-04-14 | **Status:** Phase 0

## Current State

### Already in easykubenix (native)
| Module | Resources | Status |
|---|---|---|
| `common.nix` | PriorityClasses | ✅ |
| `infrastructure.nix` | Namespaces, NetworkPolicy, PSS | ✅ |
| `gpu-miners.nix` | 6 lolMiner deployments (forge×4, zephyr, nexus) | ⚠️ nexus not deployed |
| `mining.nix` | xmrig (zephyr, nexus, sentry, proxy) | ✅ |
| `haven.nix` | haven deployment | ✅ |
| `searxng.nix` | searxng (2 replicas) | ✅ |

### importyaml (needs conversion)
| Module | Source | Resources |
|---|---|---|
| `ai-inference.nix` | `ai-inference-clean.yaml` (13KB) | grafana, open-webui, ingresses, SAs, RBAC, 6 ConfigMaps |
| `nixkube.nix` | `nixkube-clean.yaml` (28KB) | nix-node DaemonSet, proxy, nix-cache StatefulSet, CMs |
| `ingress.nix` | `caddy-ingress-controller.yaml` (5KB) | caddy controller, SA, ClusterRole, ConfigMap |

### systemd services (candidates for migration)
| Service | Nodes | Type | K8s Pattern | Priority |
|---|---|---|---|---|
| `llamafile` | zephyr | GPU inference (CUDA) | Deployment + hostPath | P0 |
| `llama-server` | sentry | GPU inference (ROCm) | Deployment + hostPath | P0 |
| `prometheus-node-exporter` | all 4 | Host metrics | DaemonSet | P1 |
| `prometheus-mining-exporter` | nexus, forge, sentry | GPU metrics | DaemonSet + hostPath | P1 |
| `xmrig-proxy` | zephyr | Stratum proxy | Deployment | P1 |
| `ai-inference-gateway` | zephyr, sentry | API gateway | Deployment | P2 |
| `ai-inference-monitor` | zephyr, nexus, sentry | Health monitor | Deployment | P2 |
| `prometheus` | nexus, sentry | Metrics | StatefulSet + PVC | P2 |
| `alertmanager` | nexus, sentry | Alerting | StatefulSet | P2 |
| `loki` | sentry | Log aggregation | StatefulSet + PVC | P3 |
| `alert-webhook` | sentry | Alert relay | Deployment | P3 |
| `vaultwarden` | zephyr | Password manager (podman) | Deployment + PVC | P3 |
| `host-dashboard` | all 4 | Host info dashboard | DaemonSet | P3 |

### Stay systemd (hardware/desktop bound)
- display-manager, ckb-next, rgb-temperature-control, fail2ban
- gaming-detection, mining-coordinator (need host process visibility)
- keepalived (VIP failover), caddy (local proxy), claude-code-router
- gpu-proxy-cpp (GPU scheduling), syncthing (filesystem)
- redis, redis-ai-gateway, qdrant (stateful, low migration value)

---

## Phase 0: Cleanup (no migration, just hygiene)

- [ ] Delete orphan ConfigMaps in ai-inference namespace
- [ ] Decide on gpu-miner-nexus (deploy or remove definition)
- [ ] Add `app.kubernetes.io/managed-by: easykubenix` label to all native modules

## Phase 1: Convert importyaml → native easykubenix

- [ ] `ai-inference.nix` — convert grafana + open-webui to native, keep only active ConfigMaps
- [ ] `ingress.nix` — convert caddy controller to native
- [ ] `nixkube.nix` — convert DaemonSet + StatefulSet to native

## Phase 2: Migrate systemd → K8s (P0-P1)

- [ ] `llamafile` (zephyr) → K8s Deployment with CUDA hostPath
- [ ] `llama-server` (sentry) → K8s Deployment with ROCm hostPath
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
