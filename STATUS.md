# NixOS Cluster - Real-Time Status

**Last Updated:** 2026-03-14 21:00 | **Auto-Generated:** Manual | **Refresh:** `just cluster-status`

> **Quick Check:** Run `just cluster-status` to see current cluster state. This command works from any cluster host and proxies to zephyr for Kubernetes queries when needed.

---

## Cluster Health Overview

| Component | Status | Details |
|-----------|--------|---------|
| **Kubernetes** | 🟢 RUNNING | v1.35.0, 4 nodes joined |
| **Control Plane** | 🟢 OPERATIONAL | Zephyr: apiserver, etcd, scheduler, controller-manager |
| **Worker Nodes** | 🟢 4/4 READY | Zephyr, Nexus, Sentry, Forge |
| **Networking** | 🟢 OPERATIONAL | Flannel CNI (VXLAN), CoreDNS, Unbound cluster DNS |
| **Ingress Controller** | 🟢 DEPLOYED | Caddy Ingress (DaemonSet on 2 nodes) |
| **GPU Passthrough** | 🟢 PARTIAL | Zephyr: 2x NVIDIA (✓), Forge: 2x AMD + 2x NVIDIA (⚠️) |
| **Monitoring** | 🟢 RUNNING | Prometheus, Grafana, AlertManager, node-exporters, Caddy metrics |
| **Storage** | 🟢 OPERATIONAL | NFS shared storage, local-path provisioner |
| **GPU Marketplace** | 🟢 DEPLOYED | Auction engine coordinating mining/K8s/Akash/gaming |

---

## Kubernetes Nodes

```
NAME     STATUS   ROLES                          AGE     VERSION
zephyr   Ready    ai-workstation,control-plane   15m     v1.35.0
forge    Ready    gpu-compute                    16m     v1.35.0
nexus    Ready    storage                        15m     v1.35.0
sentry   Ready    monitoring                     15m     v1.35.0
```

> **Note:** Node ages reflect CIDR fix + role label application. Roles describe node function for pod scheduling.
> etcd HA cluster (zephyr, nexus, sentry) remains unchanged from original setup.

### GPU Resources by Node

| Node | NVIDIA GPUs | AMD GPUs | Status |
|------|-------------|----------|--------|
| **Zephyr** | 2 (RTX 3090 + 3060 Ti) | 0 | ✅ Fully operational |
| **Nexus** | 1 (RTX 3060 Ti) | 0 | ✅ Operational |
| **Forge** | 2 (RTX 4060) | 2 (RX 5700 XT) | ⚠️ NVIDIA plugin issues |
| **Sentry** | 0 | 1 (RX 5600 XT) | ✅ Operational |

---

## Migration Progress (Kubernetes)

| Phase | Status | Completion | Notes |
|-------|--------|------------|-------|
| **Phase 1: Foundation** | ✅ COMPLETE | 100% | Control plane, networking, CoreDNS |
| **Phase 2: Worker Nodes** | ✅ COMPLETE | 100% | All nodes joined, correct CIDRs, DNS functional |
| **Phase 3: Stateful Services** | ⏳ PENDING | 0% | Not started |
| **Phase 4: Stateless Services** | 🟢 STARTED | 5% | **Caddy Ingress deployed, backend migration pending** |
| **Phase 5: GPU Workloads** | ⏳ PENDING | 0% | Not started |
| **Phase 6: Monitoring** | ✅ COMPLETE | 100% | Prometheus + Grafana running, **Caddy metrics configured** |
| **Phase 7: Cleanup** | ⏳ PENDING | 0% | Not started |

**Overall Progress:** ~40% complete (3 of 7 phases)

---

## Services Running

### Systemd Services (Active)
- **AI/ML:** ai-inference-monitor, qdrant
- **Databases:** glitchtip-postgres, glitchtip-redis
- **Web:** glitchtip-web, glitchtip-worker, n8n, searx, caddy, home-assistant
- **Monitoring:** prometheus, grafana, alertmanager, prometheus-node-exporter, prometheus-nvidia-gpu-exporter, promtail
- **Kubernetes:** etcd, kube-apiserver, kube-scheduler, kube-controller-manager, kubelet, kube-proxy, containerd, docker
- **Networking:** avahi, rpcbind, nfs-*
- **Mining:** lolminer-nvidia

### Kubernetes Pods (Namespaces)
- **ingress-system:** caddy-ingress DS (2 pods on nexus, sentry)
- **kube-system:** coredns, flannel, nvidia-device-plugin, amd-gpu-device-plugin
- **kube-flannel:** flannel DS pods
- **local-path-storage:** local-path-provisioner
- **mining:** xmrig-proxy
- **test-echo:** echo-server test deployment
- **akash-services:** akash-provider, operator-* services
- **default:** test pods (gpu-test, test-nfs, etc.)

---

## Known Issues

| Priority | Issue | Impact | Status |
|----------|-------|--------|--------|
| 🔴 HIGH | Forge RTX 4060 GPU passthrough | NVIDIA workloads can't schedule on Forge | Investigating |
| 🟡 MEDIUM | Storage classes not fully tested | PVC creation may fail | Testing needed |
| 🟢 LOW | ~~Forge nixos-share mount~~ | ~~Read-write mount~~ | ✅ FIXED - Now read-only |
| 🟢 LOW | NFS hard mounts | System hangs if NFS down | ✅ FIXED - Soft mounts with 10s timeout |
| 🟢 LOW | GPU workload coordination needed | Mining vs K8s GPU conflict | Design phase |

---

## Recent Changes

**2026-03-14 21:00:**
- ✅ **TESTED: Garage S3 API from Kubernetes** - Successfully connected, authenticated, listed buckets
- ✅ **CREATED: Kubernetes S3 key** - Dedicated `kubernetes-s3-key` for K8s Garage access
- ✅ **VERIFIED: Garage 3-node cluster** - All nodes healthy (zephyr, nexus, sentry) with 4.4TB total
- ✅ **FIXED: NFS documentation** - Corrected inaccuracies about Zephyr /data mounts and Forge nixos-share
- ✅ **VERIFIED: All nixos-share mounts** - Read-only on all remote nodes (Nexus, Forge, Sentry)
- ✅ **CONFIGURED: NFS graceful failure** - Changed to soft mounts with 10s timeout (was hard/hang forever)
- 📝 **CREATED: docs/nfs-graceful-failure.md** - Complete documentation for NFS behavior
- 📝 **UPDATED: storage-*.md docs** - Accurate storage architecture documentation

**2026-03-14 20:30:**
- ✅ **FIXED: Kubernetes networking** - Resolved CIDR mismatch (10.1.x.0/24 → 10.244.x.0/24)
- ✅ **DEPLOYED: CoreDNS** - 2 replicas running, DNS fully functional
- ✅ **LABELED: Node roles** - Applied functional role labels (ai-workstation, gpu-compute, storage, monitoring)
- ✅ **VERIFIED: DNS resolution** - Service discovery working (service.namespace.svc.cluster.local)
- ✅ **CREATED: manifests/coredns.yaml** - CoreDNS deployment manifest for cluster
- 📝 **UPDATED: STATUS.md, ROADMAP.md** - Documentation current as of Phase 2 complete

**2026-03-14 14:00:**
- ✅ **DEPLOYED: Caddy Ingress Controller** (DaemonSet on nexus, sentry)
- ✅ **CONFIGURED: Prometheus metrics scraping** for Caddy admin API
- ✅ **UPDATED: network-constants.nix** with Caddy port definitions
- ✅ **CREATED: kubernetes-manifests/ingress/** with full Caddy configuration
- 📝 **UPDATED: prometheus.nix** with Caddy ingress scrape job

**2026-03-14:**
- Fixed NixOS build issues (Python corruption, substituter URLs, NFS automount)
- Fixed agenix boot error (removed corrupted tplink-password.age)
- Fixed DOCUMENTATION_INDEX.md hookify rules section (removed incorrect paths)
- Fixed CNI tmpfiles directive (will fully apply on next reboot)

**2026-03-13:**
- Created STATUS.md for real-time cluster state tracking
- Fixed documentation drift (ROADMAP.md, DOCUMENTATION_INDEX.md)
- Verified monitoring stack operational
- Verified 4-node cluster joined and operational

**2026-03-12:**
- Added StorageClasses for cluster workloads
- Enabled cluster-hosts module

**2026-03-08:**
- Bootstraped Kubernetes control plane on Zephyr
- Joined all 4 worker nodes
- Deployed Flannel CNI and CoreDNS
- Deployed NVIDIA and AMD device plugins

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
2. **THIS WEEK:** Begin Phase 3 (Stateful Services migration - GlitchTip DB)
3. **ONGOING:** Investigate Forge RTX 4060 Ada Lovelace GPU plugin issue

---

**Status File Version:** 1.0 | **Location:** `/etc/nixos/STATUS.md`
