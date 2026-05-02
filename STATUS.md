# NixOS Cluster - Real-Time Status

**Last Updated:** 2026-05-02 | **Refresh:** `./scripts/update-status.sh`

> **Quick Check:** Run `just cluster-status` to see current cluster state. This command works from any cluster host and proxies to zephyr for Kubernetes queries when needed.
>
> **Note:** For the most current state, run `kubectl get nodes` and `kubectl get pods --all-namespaces`.

---

## Cluster Health Overview

| Component | Status | Details |
|-----------|--------|---------|
| **Kubernetes** | 🟢 RUNNING | v1.34.5+k3s1, 4 nodes joined |
| **Control Plane** | 🟢 OPERATIONAL | Zephyr: apiserver, etcd, scheduler, controller-manager |
| **Worker Nodes** | 🟢 4/4 READY | Zephyr, Nexus, Sentry, Forge |
| **Networking** | 🟢 OPERATIONAL | Flannel CNI (VXLAN), CoreDNS, Unbound cluster DNS |
| **Ingress Controller** | 🟢 DEPLOYED | Caddy Ingress (DaemonSet on 2 nodes) |
| **GPU Passthrough** | 🟢 PARTIAL | Zephyr: 2x NVIDIA (✓), Forge: 2x AMD + 2x NVIDIA (⚠️) |
| **Monitoring** | 🟢 RUNNING | Prometheus, Grafana, AlertManager, node-exporters, Caddy metrics |
| **Storage** | 🟢 OPERATIONAL | NFS shared storage, local-path provisioner |
| **GPU Marketplace** | 🟢 DEPLOYED | Auction engine coordinating mining/K8s/gaming |

---

## Kubernetes Nodes

```
NAME     STATUS    ROLES                AGE   VERSION
forge    Ready     <none>               21d   v1.34.5+k3s1
nexus    Unknown   control-plane,etcd   21d   v1.34.5+k3s1
sentry   Ready     control-plane,etcd   21d   v1.34.5+k3s1
zephyr   Ready     control-plane,etcd   19d   v1.34.5+k3s1
```

> **Note:** Node ages reflect CIDR fix + role label application. Roles describe node function for pod scheduling.
> etcd HA cluster (zephyr, nexus, sentry) remains unchanged from original setup.

### GPU Resources by Node

| Node | NVIDIA GPUs | AMD GPUs | CUDA | ROCm | Vulkan |
|------|-------------|----------|------|------|--------|
| **Zephyr** | 2 (RTX 3090 + 3060 Ti) | 0 | ✅ | - | ✅ |
| **Nexus** | 1 (RTX 3060 Ti) | 0 | ✅ | - | ✅ |
| **Forge** | 2 (RTX 4060) | 2 (RX 5700 XT) | ✅ | ✅ | ✅ |
| **Sentry** | 0 | 1 (RX 5600 XT) | - | ✅ | ✅ |

> **Note (2026-03-16):** CUDA issue resolved by removing `allowUnsupportedSystem = true;` from flake.nix. See `docs/CUDA_TROUBLESHOOTING.md` for details.

---

## Migration Progress (Kubernetes)

| Phase | Status | Completion | Notes |
|-------|--------|------------|-------|
| **Phase 1: Foundation** | ✅ COMPLETE | 100% | Control plane, networking, CoreDNS |
| **Phase 2: Worker Nodes** | ✅ COMPLETE | 100% | All nodes joined, correct CIDRs, DNS functional |
| **Phase 3: Stateful Services** | ✅ COMPLETE | 95% | **GlitchTip PostgreSQL migrated** (2026-03-19) |
| **Phase 4: Stateless Services** | ✅ COMPLETE | 95% | **GlitchTip web/worker/redis, SearXNG migrated** (2026-03-19), Caddy Ingress, n8n, home-assistant |
| **Phase 5: GPU Workloads** | ✅ COMPLETE | 95% | **llama.cpp deployed, Gateway integrated, tested** (2026-03-19) |
| **Phase 6: Monitoring** | ✅ COMPLETE | 100% | Prometheus + Grafana running, **Caddy metrics configured** |
| **Phase 7: Cleanup** | ✅ COMPLETE | 95% | **Removed obsolete manifests, finalized documentation** (2026-03-19) |

**Overall Progress:** ✅ **95% COMPLETE** (All 7 phases finished, known issues remain)

**Known Issues:**
- ⚠️ **SearXNG search:** HTTP 403 errors from external engines, MCP gateway unable to use web search (2026-03-21)
- ⚠️ **Monitor brightness:** ASUS/Acer displays not controllable via Plasma slider (EDID limitation, hardware workaround required)
- ⚠️ **Gaming detection:** Using Volcano scheduler instead of YuniKorn (migration completed, docs need update)

---

## Services Running

### Kubernetes Pods by Namespace

```
NAMESPACE        NAME                                          READY   STATUS              RESTARTS         AGE     IP             NODE     NOMINATED NODE   READINESS GATES
ai-coding        claude-code-7c66bbd5df-jpm29                  2/2     Running             0                33h     10.244.1.143   nexus    <none>           <none>
ai-coding        opencode-74d7dcc864-22hxj                     2/2     Running             0                33h     10.244.1.144   nexus    <none>           <none>
ai-inference     ai-inference-gateway-7486445f95-jqwrz         1/1     Running             0                134m    10.244.1.38    nexus    <none>           <none>
ai-inference     grafana-54df9fcd99-j6pcw                      1/1     Running             0                2d11h   10.244.1.55    nexus    <none>           <none>
ai-inference     kb-mcp-79dd8d5495-j5p4x                       0/1     ErrImageNeverPull   0                33h     10.244.1.146   nexus    <none>           <none>
ai-inference     knowledge-fabric-api-5d8b8c8747-2tp5j         1/1     Running             0                2d5h    10.244.1.102   nexus    <none>           <none>
ai-inference     llama-server-sentry-6bb9d877c7-7nwsj          1/1     Running             0                133m    10.1.1.140     sentry   <none>           <none>
ai-inference     llama-server-zephyr-3060ti-6cb7655bcf-9zflk   1/1     Running             4 (4m40s ago)    4h39m   10.1.1.110     zephyr   <none>           <none>
ai-inference     llama-server-zephyr-59dc749559-fnfvj          1/1     Running             4 (4m40s ago)    4h35m   10.1.1.110     zephyr   <none>           <none>
ai-inference     open-webui-8866f5849-m6mxl                    1/1     Running             0                2d7h    10.244.1.60    nexus    <none>           <none>
ai-inference     prometheus-c4ffb886d-7msq4                    1/1     Running             0                2d7h    10.244.1.61    nexus    <none>           <none>
ai-inference     qdrant-0                                      1/1     Running             0                2d5h    10.244.1.101   nexus    <none>           <none>
ai-inference     redis-687b88d554-h45xq                        1/1     Running             0                2d10h   10.244.1.46    nexus    <none>           <none>
automation       activepieces-5fb75896b6-mxqng                 1/1     Running             2 (3d17h ago)    7d5h    10.244.1.6     nexus    <none>           <none>
automation       n8n-86bf9b6889-plk9g                          1/1     Running             2 (3d17h ago)    7d5h    10.244.1.7     nexus    <none>           <none>
automation       postgres-activepieces-0                       1/1     Running             1 (3d17h ago)    7d5h    10.244.1.5     nexus    <none>           <none>
automation       postgres-n8n-0                                1/1     Running             1 (3d17h ago)    7d5h    10.244.1.8     nexus    <none>           <none>
automation       redis-activepieces-54dcdf6c86-6ptx5           1/1     Running             1 (3d17h ago)    7d5h    10.244.1.9     nexus    <none>           <none>
cert-manager     cert-manager-5f9ddb88b4-7jn64                 1/1     Running             7 (4m37s ago)    11d     10.244.3.7     sentry   <none>           <none>
cert-manager     cert-manager-cainjector-9bb5d7d75-x9q78       1/1     Running             4 (7m32s ago)    11d     10.244.3.8     sentry   <none>           <none>
cert-manager     cert-manager-webhook-7fc8569958-v2k95         1/1     Running             1 (7d12h ago)    11d     10.244.3.6     sentry   <none>           <none>
custom-metrics   prometheus-adapter-6965bf6f4-wttkz            1/1     Running             0                2d6h    10.244.1.65    nexus    <none>           <none>
default          debug-patch                                   0/1     StartError          0                4h42m   10.244.5.13    forge    <none>           <none>
haven            haven-6df4d8c688-4gzxb                        1/1     Running             5 (3d17h ago)    10d     10.1.1.120     nexus    <none>           <none>
ingress-nginx    ingress-nginx-controller-86c5998465-gg8lf     1/1     Running             2 (3d17h ago)    11d     10.244.1.12    nexus    <none>           <none>
ingress-system   caddy-ingress-controller-67bd8c745c-45p87     1/1     Running             0                109m    10.244.1.40    nexus    <none>           <none>
ingress-system   caddy-ingress-controller-67bd8c745c-cvw95     1/1     Running             0                109m    10.244.1.39    nexus    <none>           <none>
ingress-system   caddy-ingress-controller-6f9d776bc4-bdzbq     0/1     Completed           2 (3d17h ago)    11d     <none>         nexus    <none>           <none>
ingress-system   caddy-ingress-controller-6f9d776bc4-nmdpc     0/1     Completed           2 (3d17h ago)    11d     10.244.1.15    nexus    <none>           <none>
kube-system      coredns-86bbcbc8fb-g7vhr                      1/1     Running             20 (4m40s ago)   4d7h    10.244.0.2     zephyr   <none>           <none>
kube-system      local-path-provisioner-54684b46f4-t49gx       1/1     Running             0                2d6h    10.244.1.70    nexus    <none>           <none>
kube-system      local-path-provisioner-6d4f6d6666-x5qzb       0/1     Completed           6 (3d17h ago)    8d      <none>         nexus    <none>           <none>
kube-system      metrics-server-b5b44cf9-ff4l5                 1/1     Running             3 (3d17h ago)    8d      10.1.1.120     nexus    <none>           <none>
kube-system      nvidia-device-plugin-daemonset-l7k28          1/1     Running             9 (4m40s ago)    6d6h    10.244.0.5     zephyr   <none>           <none>
kube-system      nvidia-device-plugin-daemonset-rchmc          1/1     Running             1 (3d17h ago)    6d6h    10.244.1.10    nexus    <none>           <none>
kube-system      nvidia-device-plugin-daemonset-sxp9b          1/1     Running             1 (33h ago)      6d6h    10.244.5.9     forge    <none>           <none>
mining           gpu-miner-forge-amd-0-65f4fb7655-f5hrn        1/1     Running             0                26h     10.1.1.130     forge    <none>           <none>
mining           gpu-miner-forge-amd-1-85784657cc-5dkrn        1/1     Running             0                26h     10.1.1.130     forge    <none>           <none>
mining           gpu-miner-forge-nvidia-0-78679b8f5c-qfd2v     1/1     Running             0                26h     10.1.1.130     forge    <none>           <none>
mining           gpu-miner-forge-nvidia-1-7d54948766-czc68     1/1     Running             0                26h     10.1.1.130     forge    <none>           <none>
mining           gpu-miner-nexus-848fb4f76f-p6n8s              1/1     Running             0                26h     10.1.1.120     nexus    <none>           <none>
mining           xmrig-nexus-688c755b9c-xh4rw                  1/1     Running             0                27h     10.1.1.120     nexus    <none>           <none>
mining           xmrig-proxy-5bf674695d-59fsm                  1/1     Running             2 (3d17h ago)    12d     10.1.1.120     nexus    <none>           <none>
mining           xmrig-sentry-59d685d768-2f74l                 1/1     Running             0                27h     10.1.1.140     sentry   <none>           <none>
monitoring       alert-webhook-56dd6d9ff6-xf7th                1/1     Running             9 (4m40s ago)    33h     10.244.0.4     zephyr   <none>           <none>
monitoring       alloy-6kbgn                                   1/1     Running             0                34h     10.1.1.120     nexus    <none>           <none>
monitoring       alloy-fctc6                                   1/1     Running             9 (4m40s ago)    34h     10.1.1.110     zephyr   <none>           <none>
monitoring       alloy-g78dh                                   1/1     Running             0                34h     10.1.1.140     sentry   <none>           <none>
monitoring       alloy-mkmvx                                   1/1     Running             0                34h     10.1.1.130     forge    <none>           <none>
```

> **Note:** Showing first 50 pods. Run `kubectl get pods --all-namespaces` for full list.

### Pod Summary by Namespace
```
     14 monitoring
     11 ai-inference
      8 mining
      7 kube-system
      6 search
      6 nixkube
      5 automation
      4 ingress-system
      3 cert-manager
      2 ai-coding
      1 tailscale
      1 orchestration
      1 ingress-nginx
      1 haven
      1 default
      1 custom-metrics
```

---

## Recent Changes

**2026-04-26 15:34:15:**
- 🔄 **AUTO-UPDATED:** STATUS.md regenerated from current cluster state
- 📊 **CLUSTER STATUS:** All nodes Ready, control plane operational

**2026-03-21 12:30:**
- ✅ **DOCUMENTATION:** Phase 2 audit complete - archive consolidated, false completion claims removed
- ✅ **UPDATED:** STATUS.md accuracy improved to 95% with known issues
- ✅ **UPDATED:** ROADMAP.md phases 3-5 marked 95% complete with known issues
- 📁 **ARCHIVED:** 10+ incident reports moved to `docs/incidents/2026-03-21/`

**2026-03-21 11:10:**
- ✅ **COMPLETE: Phase 7 Cleanup** - Removed obsolete deployment manifests (test files, failed deployments)
- ✅ **FINALIZED: Migration documentation** - All 7 phases 100% complete
- ✅ **CLEANED: kubernetes-manifests/** - Removed test manifests, old deployment attempts, obsolete docs
- 📝 **UPDATED: STATUS.md** - Phase 7 marked complete, overall progress 100%

**2026-03-19 16:45:**
- ✅ **MIGRATED: SearXNG** - Search service now running on Kubernetes (search namespace)
- ✅ **MIGRATED: GlitchTip** - Full stack (PostgreSQL, Redis, web, worker) on Kubernetes
- ✅ **DEPLOYED: n8n** - Workflow automation on Kubernetes
- ✅ **DEPLOYED: home-assistant** - Smart home platform on Kubernetes
- 📊 **MONITORING:** Caddy metrics configured and scraping successfully

**2026-03-18 14:20:**
- ✅ **CONTROL PLANE ROBUSTNESS:** Phase 5 complete - etcd quorum protection, apiserver HA, graceful degradation
- ✅ **REFACTORED:** Compute workload monitor to dedicated module (`modules/system/compute-workload-monitor.nix`)
- ✅ **IMPLEMENTED:** Kubernetes GPU workload detection (Phase 1 of compute scheduler)
- 📝 **DOCUMENTED:** `docs/kubernetes/compute-workload-monitor-refactor.md`

---

## System Health Metrics

### Node Resource Usage
```
Node metrics not available (metrics-server not deployed)
```

### Pod Resource Usage
```
Pod metrics not available (metrics-server not deployed)
```

---

## Quick Reference

### Common Commands
```bash
# Cluster status
just cluster-status

# Node status
kubectl get nodes -o wide

# Pod status
kubectl get pods --all-namespaces

# Service status
kubectl get svc --all-namespaces

# Logs
kubectl logs -f <pod-name> -n <namespace>

# Exec into pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash
```

### Troubleshooting
```bash
# Check node not ready
kubectl describe node <node-name>

# Check pod crashes
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Check service connectivity
kubectl get endpoints <service-name> -n <namespace>
```

---

**Auto-Generated:** 2026-04-26 15:34:15
**Update Script:** `scripts/update-status.sh`
**Run Manually:** `sudo ./scripts/update-status.sh`
**Auto-Refresh:** Hourly via systemd timer (status-update.timer)
