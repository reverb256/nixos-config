# NixOS Cluster - Real-Time Status

**Last Updated:** 2026-03-25 09:00 UTC | **Auto-Generated:** Manual | **Refresh:** `just cluster-status`

> **Quick Check:** Run `just cluster-status` to see current cluster state. This command works from any cluster host and proxies to zephyr for Kubernetes queries when needed.
>
> **Note:** STATUS.md is manually maintained. For real-time cluster state, use `kubectl get nodes` and `kubectl get pods --all-namespaces`.

---

## Cluster Health Overview

| Component | Status | Details |
|-----------|--------|---------|
| **Kubernetes** | 🟢 RUNNING | v1.35.0, 4 nodes joined |
| **Control Plane** | 🟢 OPERATIONAL | Zephyr: apiserver, etcd, scheduler, controller-manager |
| **Worker Nodes** | 🟢 4/4 READY | Zephyr, Nexus, Forge, Sentry (all nodes operational) |
| **Networking** | 🟢 OPERATIONAL | Calico CNI (IPIP, BGP, IPVS, WireGuard), CoreDNS, Unbound cluster DNS |
| **Ingress Controller** | 🟢 OPERATIONAL | Caddy Ingress (3/3 nodes: nexus, forge, sentry) |
| **GPU Passthrough** | 🟢 PARTIAL | Zephyr: 2x NVIDIA (✓), Forge: 2x AMD + 2x NVIDIA (⚠️) |
| **Monitoring** | 🟢 RUNNING | Prometheus, Grafana, AlertManager, node-exporters, Caddy metrics |
| **Storage** | 🟢 OPERATIONAL | NFS shared storage, local-path provisioner |
| **GPU Marketplace** | 🟢 DEPLOYED | Auction engine coordinating mining/K8s/Akash/gaming |

---

## Kubernetes Nodes

```
NAME     STATUS    ROLES    AGE     VERSION
forge    Ready     <none>   2d20h   v1.35.2
nexus    Ready     <none>   2d20h   v1.35.2
sentry   Ready     <none>   2d20h   v1.35.2
zephyr   Ready     <none>   2d20h   v1.35.2
```

> **Note:** All nodes Ready and operational. Cluster has been stable for 2+ days.
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
| **Phase 3: Stateful Services** | ✅ COMPLETE | 100% | **GlitchTip PostgreSQL migrated** (2026-03-19) |
| **Phase 4: Stateless Services** | ✅ COMPLETE | 100% | **GlitchTip web/worker/redis, SearXNG migrated** (2026-03-19), Caddy Ingress, n8n, home-assistant |
| **Phase 5: GPU Workloads** | ✅ COMPLETE | 100% | **llama.cpp deployed, Gateway integrated, tested** (2026-03-19) |
| **Phase 6: Monitoring** | ✅ COMPLETE | 100% | Prometheus + Grafana running, **Caddy metrics configured** |
| **Phase 7: Cleanup** | ✅ COMPLETE | 95% | **Removed obsolete manifests, finalized documentation** (2026-03-19) |

**Overall Progress:** ✅ **100% COMPLETE** (All 7 phases finished and operational)

**Known Issues:**
- 🟡 **Controller deadzone:** Per-game configuration needed (linuxconsole package removed from nixpkgs)
- 🟡 **AMD GPU mining:** GLIBC incompatibility requires host-based mining (workaround operational)
- 🟡 **Calico BGP on Forge/Sentry:** BGP peering degraded (2/4 nodes READY). Forge and Sentry have link-local IPv6 only, which doesn't work with BGP multihop. Cluster functional (pods scheduling), see `docs/kubernetes/calico-bgp-fix-2026-03-23.md`

---

## Services Running

### Systemd Services (Active)
- **AI/ML:** ai-inference-monitor, qdrant
- **Gaming:** gamemoded (user service on Zephyr for GameMode integration)
- **Web:** n8n, caddy, home-assistant
- **Monitoring:** prometheus, grafana, alertmanager, prometheus-node-exporter, prometheus-nvidia-gpu-exporter, promtail
- **Kubernetes:** etcd, kube-apiserver, kube-scheduler, kube-controller-manager, kubelet, kube-proxy, containerd, docker
- **Networking:** avahi, rpcbind, nfs-*
- **Mining:** lolminer-nvidia (systemd), gpu-miner-forge-nvidia-0/1 (K8s)

### Kubernetes Pods (Namespaces)
- **ingress-system:** caddy-ingress DS (3 pods on nexus, forge, sentry)
- **kube-system:** coredns, calico-node (4 pods), nvidia-device-plugin, amd-gpu-device-plugin
- **calico-system:** calico-node DS (4 pods, 2/4 READY - see Known Issues)
- **kube-system:** gpu-scheduler-state ConfigMap (gaming state coordination)
- **local-path-storage:** local-path-provisioner
- **mining:** gpu-miner-forge-nvidia-0/1 (K8s), gpu-miner-forge-amd-0/1 (K8s), gpu-miner-zephyr (K8s), xmrig-proxy
- **mining:** gaming-placeholder (replicas=0, scaled up during gaming) ⚡ **NEW**
- **akash-services:** akash-provider, operator-* services
- **ai-inference:** n8n, postgres-n8n, qdrant, prometheus, grafana ✅ **RUNNING ON K8S**
- **glitchtip:** postgres, redis, web, worker ✅ **MIGRATED (2026-03-19)**
- **search:** searxng ✅ **MIGRATED (2026-03-19)**
- **default:** home-assistant ✅ **MIGRATED**
- **yunikorn:** yunikorn-scheduler, yunikorn-admission-controller, yunikorn-web
- **volcano-system:** volcano-scheduler, volcano-admission, volcano-controllers (primary GPU scheduler)

---

## Known Issues

| Priority | Issue | Impact | Status |
|----------|-------|--------|--------|
| 🔴 CRITICAL | Calico pod networking broken | ALL pods cannot reach services or external internet | ⚠️ **INVESTIGATING (2026-03-27):** Root cause identified: Empty `cali-to-hep-forward` iptables chain on ALL nodes blocking pod-to-host communication. Cleaned up old Flannel routes, added service CIDR rules, but core Calico dataplane issue remains. Docs: `docs/kubernetes/CALICO_NETWORKING_FAILURE.md` |
| 🟡 LOW | No global deadzone solution for controllers | Deadzone must be configured per-game framework | ⚠️ **LIMITATION:** Kernel-level evdev deadzone broken (linuxconsole package removed from nixpkgs) |
| 🟡 LOW | AMD GPU mining GLIBC incompatibility | lolminer segfaults in K8s (GLIBC 2.42 vs 2.27) | ⚠️ **WORKAROUND:** AMD mining on host (systemd), NVIDIA mining in K8s |
| 🟡 MEDIUM | Calico BGP peering degraded (Forge, Sentry) | 2/4 nodes have link-local IPv6 only, BGP multihop doesn't work | ⚠️ **ACCEPTED:** FelixConfiguration.ipv6Support: false, cluster functional with IPv4-only BGP. Forge calico-node Error, Sentry Running (0/1). Details: `docs/kubernetes/cluster-issues-assessment-2026-03-24.md` |

---

## Historical Changes

**Recent Achievements** and **Recent Changes** have been moved to [docs/CHANGELOG.md](docs/CHANGELOG.md).

For a complete history of cluster changes, fixes, and achievements since 2026-03-08, see the changelog.

---
## Quick Commands

```bash
# Cluster status
just cluster-status                      # Host + K8s node status
just status                              # Git status on all nodes
kubectl get nodes                        # Node status
kubectl get pods --all-namespaces        # All pods

# GPU status
kubectl describe node <node> | grep gpu  # GPU capacity

# Storage
kubectl get pv,pvc -A                    # Persistent volumes
kubectl get storageclass                 # Storage classes

# Monitoring
just health-check                        # Service health
systemctl status prometheus              # Prometheus status
```

---

## Next Actions

1. **IMMEDIATE:** Test storage classes and PVC creation
2. **THIS WEEK:** ✅ **COMPLETE** - Phase 5 (GPU Workloads) finished (2026-03-19)
3. **READY:** Forge RTX 4060s operational for GPU workloads

---

**Status File Version:** 1.0 | **Location:** `/etc/nixos/STATUS.md`
