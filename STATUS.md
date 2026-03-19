# NixOS Cluster - Real-Time Status

**Last Updated:** 2026-03-16 | **Auto-Generated:** Manual | **Refresh:** `just cluster-status`

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
| **Phase 5: GPU Workloads** | ⏳ PENDING | 0% | Not started |
| **Phase 6: Monitoring** | ✅ COMPLETE | 100% | Prometheus + Grafana running, **Caddy metrics configured** |
| **Phase 7: Cleanup** | 🟢 IN PROGRESS | 80% | Config updated, documentation aligned, removing old files |

**Overall Progress:** ~85% complete (6 of 7 phases, cleanup in progress)

---

## Services Running

### Systemd Services (Active)
- **AI/ML:** ai-inference-monitor, qdrant
- **Web:** n8n, caddy, home-assistant
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
- **akash-services:** akash-provider, operator-* services
- **ai-inference:** n8n, postgres-n8n, qdrant, prometheus, grafana ✅ **RUNNING ON K8S**
- **glitchtip:** postgres, redis, web, worker ✅ **MIGRATED (2026-03-19)**
- **search:** searxng ✅ **MIGRATED (2026-03-19)**
- **default:** home-assistant ✅ **MIGRATED**

---

## Known Issues

| Priority | Issue | Impact | Status |
|----------|-------|--------|--------|
| 🔴 HIGH | Forge RTX 4060 GPU passthrough | NVIDIA workloads can't schedule on Forge | Investigating |
| 🟡 MEDIUM | Storage classes not fully tested | PVC creation may fail | Testing needed |
| 🟢 LOW | ~~Forge nixos-share mount~~ | ~~Read-write mount~~ | ✅ FIXED - Now read-only |
| 🟢 LOW | NFS hard mounts | System hangs if NFS down | ✅ FIXED - Soft mounts with 10s timeout |
| 🟢 LOW | ~~GPU workload coordination needed~~ | Mining vs K8s GPU conflict | ✅ **SOLVED:** GPU Resource Marketplace deployed |

---

## Recent Changes

**2026-03-19 04:30:**
- ✅ **FIXED: Configuration inconsistencies** - MCP Server SearXNG URL, Caddy proxy, Prometheus/Grafana comments
- ✅ **UPDATED: Migration progress** - All service references now coherent with Kubernetes deployment
- ✅ **COMMITTED: fix(config)** - Resolved all Kubernetes migration inconsistencies (commit 8d5f638)
- ✅ **VERIFIED: All migrated services running** - 10 pods across 4 namespaces operational
- 📝 **UPDATED: STATUS.md** - Removed old systemd service references, added search namespace

**2026-03-19 03:30:**
- ✅ **MIGRATED: GlitchTip to Kubernetes** - PostgreSQL StatefulSet, Redis, Web, Worker deployments
- ✅ **CREATED:** kubernetes-manifests/glitchtip/ - Complete GlitchTip K8s manifests
- ✅ **DISABLED:** Old GlitchTip systemd services (stopped, config set to enable = false)
- ✅ **VERIFIED:** GlitchTip web accessible via port-forward (http://localhost:8000)
- ✅ **MIGRATED:** n8n and home-assistant already running on Kubernetes
- ✅ **CREATED:** NFS storage PVs (nfs-shared-pv, nfs-media-pv, nfs-backups-pv, nfs-home-pv)
- 📝 **UPDATED:** STATUS.md - Migration progress now 70% complete (5 of 7 phases)

**2026-03-16 14:30:**
- ✅ **FIXED: CUDA compute on all NVIDIA GPU hosts** - Removed `allowUnsupportedSystem` causing cuda_compat build failure
- ✅ **RESOLVED: GitHub issue #458799** - cuda_compat was being built on x86_64 due to `allowUnsupportedSystem = true`
- ✅ **ENABLED: CUDA** on Zephyr (2× NVIDIA), Nexus (1× NVIDIA), Forge (2× NVIDIA)
- ✅ **ADDED: CUDA binary cache** (cache.nixos-cuda.org) to distributed-builds.nix
- ✅ **CREATED: docs/CUDA_TROUBLESHOOTING.md** - Comprehensive CUDA setup and troubleshooting guide
- 📝 **UPDATED: STATUS.md** - GPU Resources section now shows CUDA/ROCm/Vulkan status
- 📝 **UPDATED: docs/archive/2026-03-13-x86-64-v3-migration.md** - Historical reference (removed `allowUnsupportedSystem`)
- ⏸️ **TEMPORARY: Disabled bitwarden-desktop** - electron-39 patch issue blocking builds

**2026-03-14 22:30:**
- ✅ **DEPLOYED: GPU Resource Marketplace** - Unified auction engine for GPU allocation
- ✅ **CREATED: modules/compute-market/default.nix** - Core marketplace module with bidders
- ✅ **BIDDERS IMPLEMENTED:** Mining (baseline), Kubernetes (AI workloads), Akash (leases), Gaming (override)
- ✅ **GRAFANA DASHBOARD:** Auto-provisioned dashboard for marketplace metrics
- ✅ **CONFIGURED: Prometheus metrics** on port 9200
- ✅ **DOCUMENTATION:** docs/compute-market.md with architecture, troubleshooting, testing
- 📝 **UPDATED: modules/default.nix** - Added compute-market import
- 📝 **UPDATED: hosts/zephyr/configuration.nix** - Enabled marketplace on control plane
- 📝 **UPDATED: DOCUMENTATION_INDEX.md** - Added compute-market documentation entry

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
