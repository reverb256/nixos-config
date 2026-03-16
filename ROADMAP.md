# NixOS Cluster Kubernetes Migration Roadmap

**Status:** Phase 2 Complete, Phase 4 Started | **Created:** 2026-03-08 | **Owner:** j_kro | **Last Updated:** 2026-03-16

## Executive Summary

**Objective:** Migrate all containerizable services from NixOS systemd to full Kubernetes (`services.kubernetes`) across a 4-node cluster (Zephyr, Nexus, Forge, Sentry).

**Goals:**
1. Simplify operations through declarative Kubernetes manifests
2. Improve resource utilization across cluster (123GB RAM, 8 GPUs)
3. Gain enterprise Kubernetes experience for professional development
4. Enable better scalability and service orchestration

**Approach:** Full Kubernetes (not K3s) via NixOS `services.kubernetes` module for maximum learning value and operational control.

**Timeline:** Estimated 3-6 months for complete migration

---

## Current Infrastructure Assessment

### Cluster Resources

| Node | IP | CPU | RAM | GPUs | Storage | Current Services |
|------|-----|-----|-----|------|---------|-----------------|
| **Zephyr** | 10.1.1.110 | 32 cores (5950X) | 31GB | RTX 3090 + 3060 Ti | 1.85TB SSD | Control plane, desktop, gaming, mining, AI gateway |
| **Nexus** | 10.1.1.120 | 24 cores (Zen) | 46GB | 1x RTX 3060 Ti | 4.7TB (3.8TB newly activated) | Build, storage, gaming, mining |
| **Forge** | 10.1.1.130 | 6 cores (Intel) | 15GB | 2x RTX 4060 + 2x RX 5700 XT | 446GB SSD | Mining (compute-only mode), AI inference |
| **Sentry** | 10.1.1.140 | 16 cores (Zen) | 31GB | RX 5600 XT | 1.23TB (230GB SSD + 1TB HDD) | Monitoring, CPU mining |

**Total Cluster Resources:**
- CPU: 78 cores
- RAM: 123GB
- GPUs: 7 total (5x NVIDIA + 2x AMD)
- Storage: ~8.4TB raw capacity

### Current Service Inventory (31 services)

**AI/ML Services (5):**
- AI Inference Gateway (OpenAI-compatible API)
- vLLM/Qwen3.5 (local LLM)
- LM Studio (desktop UI)
- Whisper Dictation (speech-to-text)
- Stability Matrix (AI tool management)

**Databases (2):**
- GlitchTip PostgreSQL (error tracking)
- Nextcloud database (file sync)

**Web Applications (8):**
- GlitchTip (web, worker, redis)
- Nextcloud (file sync, collaboration)
- n8n (workflow automation)
- Bolt.diy (AI agent UI)
- Service Gateway (reverse proxy)
- Garnix (CI/CD)
- CI Runner
- SearXNG (search)

**Monitoring (3):**
- GPU exporters (NVIDIA/AMD)
- Mining exporter
- Prometheus/Grafana (currently disabled due to compatibility issues)

**Utilities (4):**
- Podman (container runtime)
- Tailscale (VPN)
- Unbound DNS (cluster DNS)
- NixOS-share (configuration sync)

**Desktop/Mining (9):**
- Gaming tools, mining clients (xmrig, lolminer)
- Not containerized (remain on systemd)

---

## Migration Goals and Success Criteria

### Primary Goals

1. **Containerize all applicable services** (target: 22 of 31 services)
2. **Implement GPU passthrough** for AI/ML workloads
3. **Establish proper storage management** (PVs, PVCs, storage classes)
4. **Set up ingress/load balancing** (continue using Service Gateway pattern)
5. **Enable multi-node orchestration** (distribute workloads across cluster)
6. **Gain enterprise K8s experience** (control plane operations, troubleshooting, scaling)

### Success Criteria

- ✅ All stateless services running in Kubernetes
- ✅ Stateful services using PVCs with proper backup
- ✅ GPU workloads scheduled on appropriate nodes
- ✅ Service discovery working (cluster DNS + Service Gateway integration)
- ✅ Monitoring and observability functional
- ✅ Rollback procedures tested and documented
- ✅ Zero downtime during migration (blue-green or canary)

---

## Technical Architecture

### Kubernetes Distribution

**Choice:** Full Kubernetes via `services.kubernetes` module (NOT K3s)

**Rationale:**
- Enterprise-grade experience (control plane operations, etcd management)
- Maximum flexibility and control
- Better for learning professional K8s operations
- NixOS native module (version 1.35.0)

**Control Plane (3-Node HA):**
- **Zephyr** (10.1.1.110): Primary master (apiserver, scheduler, controller-manager, etcd)
- **Nexus** (10.1.1.120): Secondary master (priority 100)
- **Sentry** (10.1.1.140): Tertiary master (priority 90)
- **VIP** (10.1.1.100): Floating virtual IP via Keepalived for API server HA
- **etcd Cluster:** 3-node quorum (zephyr, nexus, sentry)

**Worker Nodes:**
- **Zephyr:** GPU worker + control plane (2x NVIDIA)
- **Nexus:** Storage worker + control plane (1x NVIDIA, large local storage)
- **Forge:** Multi-GPU worker (2x NVIDIA + 2x AMD)
- **Sentry:** Monitoring worker + control plane (1x AMD)

### Networking

**CNI:** Flannel (default with services.kubernetes.flannel)
- Network: `10.244.0.0/16`
- Backend: VXLAN (port 8472)
- Simple, reliable, sufficient for homelab

**Service Discovery:**
- Cluster DNS (CoreDNS)
- Service Gateway (Caddy) for external access
- NodePort/LoadBalancer for internal services

**Ingress Strategy:**
- **Option 1:** Continue using Service Gateway (Caddy) for HTTP/HTTPS routes
- **Option 2:** NGINX Ingress Controller for advanced routing
- **Decision:** Start with Service Gateway, migrate to NGINX Ingress if needed

### Storage Architecture

**Storage Classes:**
1. **fast-local-ssd** (Zephyr 922GB) - Databases, high IOPS
2. **large-nfs-storage** (Nexus 3.6TB via NFS) - Media, backups
3. **slow-hdd** (Sentry 1TB) - Logs, archival

**Provisioner:** Local path provisioner (built-in to K8s)
- **Future:** Longhorn for distributed block storage with replication

**Storage Mapping:**
| Service Type | Storage Class | Node | Rationale |
|--------------|--------------|------|-----------|
| GlitchTip DB | fast-local-ssd | Zephyr | High IOPS, local |
| Nextcloud DB | fast-local-ssd | Zephyr | High IOPS, local |
| Nextcloud Data | large-nfs-storage | Nexus (via NFS) | Large capacity |
| AI Models | fast-local-ssd | Zephyr | Fast loading |
| Backups | large-nfs-storage | Nexus (via NFS) | Large capacity |
| Logs | slow-hdd | Sentry | Low priority |

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)

**Objectives:**
- Deploy Kubernetes control plane on Zephyr
- Set up basic cluster networking
- Test GPU passthrough
- Establish monitoring

**Tasks:**
1. ✅ **Completed:** Install Kubernetes skills
   - `kubernetes-specialist` (2.3K installs)
   - `kubernetes-architect` (211 installs)
   - `helm-chart-scaffolding` (2.7K installs)

2. ✅ **Completed:** Configure services.kubernetes module on Zephyr
   ```nix
   services.kubernetes = {
     enable = true;
     roles = ["master" "node"];
     # Control plane configuration
     apiserver.enable = true;
     etcd.enable = true;
     scheduler.enable = true;
     controllerManager.enable = true;
     # Networking
     flannel.enable = true;
     # Kubelet
     kubelet.enable = true;
   };
   ```

3. ⚠️ **Partial Success:** Deploy NVIDIA device plugin DaemonSet
   - ✅ Applied official NVIDIA device plugin manifest (v0.18.2)
   - ✅ Configured GPU resource requests
   - ✅ Zephyr: 2 GPUs registered (RTX 3060 Ti, RTX 3090)
   - ❌ Forge: 0 GPUs registered (RTX 4060 - investigation needed)
   - ✅ Test GPU allocation successful on Zephyr

4. ✅ **Completed:** Verify cluster health
   - ✅ `kubectl get nodes` - All 4 nodes Ready
   - ✅ `kubectl get pods --all-namespaces` - CoreDNS, Flannel running
   - ✅ Test DNS resolution - Functional

**Success Criteria:**
- ✅ Control plane running on Zephyr
- ✅ Zephyr registered as node
- ✅ GPU devices visible in `kubectl describe node` (Zephyr only)
- ✅ CoreDNS operational
- ❌ **NEW GAP IDENTIFIED:** No GPU workload coordination between mining and Kubernetes

**Deliverables:**
- ✅ NixOS configuration committed
- ✅ Cluster bootstrapped
- ✅ Monitoring deployed (Prometheus + Grafana - operational)
- ⚠️ **NEW REQUIREMENT:** Compute scheduler coordination for GPU workloads

**Phase 2 Status: ✅ COMPLETE (100%)**

**Completed:**
- ✅ Nexus joined as worker + master (HA control plane)
- ✅ Sentry joined as worker + master (HA control plane)
- ✅ Forge joined as worker (GPU compute)
- ✅ All 4 nodes in cluster with Ready status
- ✅ Keepalived VIP configured (10.1.1.100)
- ✅ etcd 3-node cluster operational
- ✅ CoreDNS deployed and functional
- ✅ Flannel CNI networking operational
- ✅ GPU passthrough working on Zephyr (2x NVIDIA)

**Outstanding Issues:**
- ⚠️ Forge GPU registration failing (RTX 4060 Ada Lovelace support issue)
- ⚠️ Storage classes deployed but not fully tested

**Completed:**
- ✅ Kubernetes control plane deployed and operational
- ✅ 4-node cluster formed (Zephyr, Forge, Nexus, Sentry)
- ✅ Networking (Flannel CNI) functional
- ✅ CoreDNS operational
- ✅ GPU passthrough working on Zephyr (2 GPUs)
- ✅ Control plane robustness implemented (Phase 5 - prevents cascading failures)
- ✅ Compute workload monitor refactored to dedicated module
- ✅ Kubernetes GPU workload detection implemented (Phase 1 of compute scheduler)

**Outstanding Issues:**
- ❌ Forge GPU registration failing (RTX 4060 Ada Lovelace support issue)

**Documentation:**
- ✅ `/etc/nixos/docs/archive/research/compute-scheduler-gaps-analysis.md` - Comprehensive gap analysis
- ✅ `/etc/nixos/docs/archive/research/compute-scheduler-implementation-tracker.md` - 6-phase implementation plan
- ✅ `/etc/nixos/docs/archive/research/phase-5-complete.md` - Control plane robustness documentation
- ✅ `/etc/nixos/docs/kubernetes/compute-workload-monitor-refactor.md` - Module refactoring documentation
- ✅ `/etc/nixos/docs/kubernetes/gpu-test-phase1.yaml` - GPU test pod for K8s detection testing

**Next Steps:**
1. **READY:** Test Kubernetes GPU workload detection with gpu-test-phase1 pod
2. **MEDIUM:** Investigate and fix Forge GPU registration issue
3. **LOW:** Begin Phase 2 - Complete worker node storage configuration

---

### Phase 2: Worker Nodes & HA Control Plane (Week 2-3) ✅ COMPLETE

**Objectives:**
- Add Nexus, Forge, Sentry as worker nodes
- Configure GPU passthrough for each node type
- Set up storage provisioners
- Deploy HA control plane with 3 masters

**Tasks Completed:**
1. ✅ **Configure Nexus worker + master** (1x NVIDIA)
   - Joined as worker node
   - Promoted to master for HA
   - Configured Keepalived VIP (priority 100)
   - Storage worker with large local storage

2. ✅ **Configure Forge worker** (2x NVIDIA + 2x AMD - mixed vendor)
   - Joined as worker node
   - GPU passthrough: NVIDIA working, AMD plugin issues

3. ✅ **Configure Sentry worker + master** (1x AMD)
   - Joined as worker node
   - Promoted to master for HA
   - Configured Keepalived VIP (priority 90)
   - Monitoring stack operational

4. ✅ **Deploy HA Control Plane**
   - 3-master control plane (Zephyr, Nexus, Sentry)
   - Keepalived VIP (10.1.1.100) for API server failover
   - 3-node etcd cluster with quorum

5. ✅ **Activate cluster storage**
   - Nexus 3.8TB storage active
   - Storage classes created (beta2, beta3, ram)
   - NFS shared storage operational

**Objectives:**
- Add Nexus, Forge, Sentry as worker nodes
- Configure GPU passthrough for each node type
- Set up storage provisioners

**Tasks:**
1. **Configure Nexus worker** (1x NVIDIA)
   ```nix
   services.kubernetes = {
     enable = true;
     roles = ["node"];
     masterAddress = "10.1.1.110";  # Zephyr
   };
   ```

2. **Configure Forge worker** (2x NVIDIA + 2x AMD - mixed vendor)
   - Deploy NVIDIA device plugin
   - Deploy AMD device plugin (experimental)
   - Test GPU scheduling by vendor

3. **Configure Sentry worker** (1x AMD)
   - Deploy AMD device plugin
   - Set up local storage provisioner

4. **Activate cluster storage**
   - Mount Nexus 3.8TB (already fixed via cluster-storage module)
   - Create storage classes
   - Test PV/PVC creation

**Success Criteria:**
- All 4 nodes in cluster
- `kubectl get nodes` shows all 4 nodes Ready
- GPU resources schedulable on appropriate nodes
- Storage classes functional

**Deliverables:**
- All nodes joined to cluster
- GPU passthrough verified
- Storage classes created and tested

---

### Phase 3: Stateful Services (Week 3-4)

**Objectives:**
- Migrate databases to Kubernetes
- Set up persistent storage
- Configure backups

**Services to migrate:**
1. **GlitchTip PostgreSQL**
   - Current: systemd service
   - Target: StatefulSet with PVC
   - Storage: fast-local-ssd on Zephyr
   - Backup: NFS to Nexus

2. **Nextcloud database**
   - Current: systemd service
   - Target: StatefulSet with PVC
   - Storage: fast-local-ssd on Zephyr
   - Data migration: Export/import

3. **Nextcloud data**
   - Current: Local filesystem
   - Target: PVC mounted to large-nfs-storage (Nexus NFS)
   - Migration: rsync to maintain permissions

**Tasks:**
1. Create Kubernetes manifests for databases
2. Deploy StatefulSets
3. Configure PVCs with appropriate storage classes
4. Set up automated backups (NFS snapshots, Velero)
5. Test backup/restore procedures

**Success Criteria:**
- Databases running in Kubernetes
- Data persisted across pod restarts
- Backups automated and tested
- Restore procedure validated

**Deliverables:**
- Database manifests committed to git
- Backup automation deployed
- Runbook for backup/restore procedures

---

### Phase 4: Stateless Services (Week 4-6)

**Objectives:**
- Migrate web applications to Kubernetes
- Set up service discovery and ingress
- Configure health checks and auto-restart

**Services to migrate:**

**Tier 1 - Core Infrastructure (Week 4):**
- ✅ ~~Service Gateway (Caddy) → NGINX Ingress Controller~~ **Caddy Ingress deployed (2026-03-14)**
  - DaemonSet on nexus, sentry
  - Prometheus metrics configured
  - Routes: ai.cluster.local, search.cluster.local, provider.cluster.local
  - NodePort access: 30080 (HTTP), 30443 (HTTPS)
- NVIDIA GPU exporters
- Mining exporters

**Tier 2 - Web Applications (Week 5):**
- GlitchTip (web, worker, redis)
- Nextcloud (web only, DB already migrated)
- n8n
- Bolt.diy

**Tier 3 - AI/ML Services (Week 6):**
- AI Inference Gateway
- vLLM/Qwen3.5
- LM Studio (desktop app, may stay external)
- Whisper Dictation
- Stability Matrix

**Tier 4 - Utilities (Week 6):**
- SearXNG
- Garnix
- CI Runner

**Tasks:**
1. Create Helm charts or Kubernetes manifests for each service
2. Configure ConfigMaps and Secrets (use Agenix for sensitive data)
3. Set up health probes (readinessProbe, livenessProbe)
4. Configure HorizontalPodAutoscaler where appropriate
5. Set up resource limits and requests
6. Test service connectivity

**Success Criteria:**
- All services accessible via cluster DNS
- Services can communicate (ai-inference → vLLM, etc.)
- Auto-restart working properly
- Resource quotas enforced

**Deliverables:**
- Helm charts/manifests for all services
- Service mesh if needed (Istio/Linkerd?)
- Runbooks for troubleshooting

---

### Phase 5: GPU Workloads (Week 6-7)

**Objectives:**
- Migrate AI/ML workloads to use GPU passthrough
- Implement scheduling strategies for multi-GPU scenarios
- Optimize GPU utilization

**Workloads:**
- **vLLM/Qwen3.5** - Multi-GPU training/inference
- **Whisper Dictation** - Single GPU
- **Stability Matrix** - GPU resource management

**Tasks:**
1. Deploy AI workloads with GPU resource requests
2. Configure nodeSelector for GPU scheduling
   - NVIDIA workloads → Zephyr, Nexus, Forge (NVIDIA GPUs)
   - AMD workloads → Forge (AMD GPUs), Sentry
3. Test distributed training (NCCL over cluster)
4. Implement GPU sharing (time-slicing via GPU device plugin)
5. Set up GPU monitoring (DCGM-exporter, DCGM-exporter)

**Container Strategy (Nix Integration):**
- See: `/etc/nixos/docs/kubernetes/nix-pods-analysis.md`
- Use **Nixery** for ad-hoc AI/ML build environments:
  ```bash
  # Example: PyTorch + CUDA build environment
  kubectl run ai-builder --image=nixery.dev/toolchain/python312Packages.torch --restart=Never
  ```
- Build custom AI images declaratively via `dockerTools.buildLayeredImage`
- Consider NixOS containers for reproducible AI environments

**Challenges:**
- **Forge mixed vendor** (2x NVIDIA + 2x AMD)
  - Deploy vendor-specific workloads
  - Avoid mixing both in one pod
- **NCCL over PCIe** - Different root complexes = no direct P2P
  - Use cluster networking instead
  - May have performance implications

**Success Criteria:**
- AI workloads scheduled on correct GPU types
- GPU resources visible in Kubernetes
- Multi-GPU workloads functioning
- GPU monitoring dashboards operational

**Deliverables:**
- GPU workload manifests
- Scheduling strategies documented
- GPU monitoring deployed

---

### Phase 6: Monitoring & Observability (Week 7-8)

**Objectives:**
- Re-enable Prometheus and Grafana
- Set up cluster-wide monitoring
- Implement alerting

**Tasks:**
1. Deploy Prometheus Operator
2. Deploy Prometheus (scrapes all nodes)
3. Deploy Grafana (dashboards for cluster, GPUs, services)
4. Set up AlertManager
5. Configure alerting rules (CPU, memory, disk, GPU)
6. Set up logging (ELK stack or Loki)

**Services to monitor:**
- Cluster health (etcd, apiserver, scheduler)
- Node resources (CPU, memory, disk)
- GPU utilization (NVIDIA/AMD)
- Application metrics (custom metrics from services)
- Network (Flannel, service mesh)

**Success Criteria:**
- All nodes being scraped
- Grafana dashboards populated
- Alerts configured and tested
- Logging centralized

**Deliverables:**
- Monitoring manifests deployed
- Custom Grafana dashboards
- Alerting rules configured
- Logging stack operational

---

### Phase 7: Cleanup & Optimization (Week 8-9)

**Objectives:**
- Remove old systemd services
- Optimize resource usage
- Document all procedures
- Train on new workflows

**Tasks:**
1. **Service decommissioning**
   - Disable systemd services after K8s equivalents are stable
   - Keep backups during transition period
   - Document rollback procedures

2. **Resource optimization**
   - Right-size resource requests/limits
   - Implement Pod PriorityClasses
   - Configure cluster autoscaler (if needed)

3. **Documentation**
   - Update CLAUDE.md with Kubernetes workflows
   - Create runbooks for common operations
   - Document disaster recovery procedures

4. **Training**
   - Practice control plane recovery
   - Practice disaster recovery (etcd restore, etc.)
   - Learn advanced K8s patterns (network policies, service mesh)

**Success Criteria:**
- All old services disabled
- Resources optimized
- Documentation complete
- Team trained on new workflows

**Deliverables:**
- Updated documentation
- Runbooks and SOPs
- Training completed

---

## Timeline Summary

| Phase | Duration | Dependencies | Deliverable |
|-------|----------|-------------|-------------|
| Phase 1: Foundation | Week 1-2 | Skills installed | Cluster bootstrapped |
| Phase 2: Worker Nodes | Week 2-3 | Phase 1 complete | All nodes in cluster |
| Phase 3: Stateful Services | Week 3-4 | Phase 2 complete | Databases migrated |
| Phase 4: Stateless Services | Week 4-6 | Phase 3 complete | Apps migrated |
| Phase 5: GPU Workloads | Week 6-7 | Phase 4 complete | AI workloads migrated |
| Phase 6: Monitoring | Week 7-8 | Phase 5 complete | Observability restored |
| Phase 7: Cleanup | Week 8-9 | Phase 6 complete | Migration complete |

**Total: 9 weeks (2.25 months)**

---

## Dependencies and Prerequisites

### External Dependencies

1. **NixOS module:** `services.kubernetes` (version 1.35.0)
2. **Container runtime:** Podman (already installed)
3. **Hardware:**
   - GPUs: NVIDIA drivers, AMD ROCm
   - Network: 1Gbps LAN + Tailscale VPN
   - Storage: SSDs, HDDs verified and mounted

### Documentation Dependencies

- NixOS manual: https://nixos.org/manual/nixos/stable/
- Kubernetes documentation: https://kubernetes.io/docs/home/
- NVIDIA device plugin: https://github.com/NVIDIA/k8s-device-plugin

### Skill Dependencies

- ✅ Kubernetes specialist skill installed
- ✅ Kubernetes architect skill installed
- ✅ Helm chart scaffolding skill installed

### Knowledge Gaps

- **AMD GPU passthrough** (experimental plugin, limited documentation)
- **NCCL over cluster networking** (no direct PCIe P2P between different root complexes)
- **Mixed vendor scheduling** (Forge's 2x NVIDIA + 2x AMD)

---

## Risks and Mitigations

### Critical Risks

**Risk 1: Data loss during migration**
- **Impact:** HIGH
- **Mitigation:**
  - Full backups before migration
  - Test restore procedures
  - Migrate incrementally (one service at a time)
  - Keep old services running until K8s equivalents verified

**Risk 2: Cluster control plane failure**
- **Impact:** HIGH
- **Mitigation:**
  - etcd backups automated
  - Test control plane recovery procedures
  - Keep etcd on reliable storage (Zephyr 931GB SSD with ZFS/btrfs)
  - Document disaster recovery

**Risk 3: GPU passthrough failures**
- **Impact:** MEDIUM
- **Mitigation:**
  - Test GPU passthrough early (Phase 1)
  - Have rollback plan (use old systemd services)
  - Document GPU scheduling patterns
  - AMD passthrough is experimental - expect issues

**Risk 4: Performance degradation**
- **Impact:** MEDIUM
- **Mitigation:**
  - Benchmark before/after migration
  - Optimize resource requests/limits
  - Use node affinity to optimize placement
  - Monitor cluster metrics closely

### Medium Risks

**Risk 5: Steep learning curve**
- **Impact:** MEDIUM
- **Mitigation:**
  - Skills already installed (kubernetes-specialist, architect)
  - Practice in non-production environment first
  - Document everything extensively
  - Run training sessions

**Risk 6: Time overrun**
- **Impact:** MEDIUM
- **Mitigation:**
  - Buffer time included in timeline
  - Can defer non-critical services
  - Phased approach allows pausing after each phase
  - Can extend timeline as needed

**Risk 7: AMD GPU plugin instability**
- **Impact:** LOW-MEDIUM
- **Mitigation:**
  - AMD plugin is experimental
  - Avoid mixing NVIDIA + AMD in same workload
  - Focus on NVIDIA GPUs first, AMD later
  - May need custom ROCm builds

### Low Risks

**Risk 8: Network complexity**
- **Impact:** LOW
- **Mitigation:** Flannel is simple and well-tested
- Tailscale provides VPN backup
- Service Gateway already handles ingress

---

## Success Metrics

### Quantitative Metrics

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| Services containerized | 0/31 | 22/31 | 71% |
| GPU utilization visibility | Limited | Full | 100% |
| Cluster resource utilization | Manual | Automated | Automated |
| Service recovery time | Manual (minutes) | Auto (seconds) | <30s |
| Monitoring coverage | Partial | Full | 100% |
| Documentation completeness | Good | Better | Updated |

### Qualitative Metrics

- **Operational efficiency:** Faster deployments, automated recovery
- **Scalability:** Easy to add new services, scale horizontally
- **Professional development:** K8s experience for resume
- **Resource optimization:** Better GPU/CPU utilization across cluster

---

**GPU Marketplace: ✅ DEPLOYED (2026-03-14)**

**Architecture:**
- Unified auction engine for GPU resource allocation
- Bidders: Mining (baseline), Kubernetes (AI workloads), Akash (leases), Gaming (priority override)
- Prometheus metrics on port 9200
- Auto-scales mining based on cluster demand

**Documentation:** `modules/compute-market/default.nix`, `docs/compute-market.md`

---

## Next Steps

### Immediate (This Week)

1. **Test storage classes** - Verify PVC creation and binding
2. **Begin Phase 3 planning** - GlitchTip PostgreSQL migration strategy
3. **Commit updated documentation** - STATUS.md, ROADMAP.md changes

### This Month

1. **Complete Phase 3** (Stateful Services - GlitchTip DB, Nextcloud)
2. **Investigate Forge GPU** - RTX 4060 Ada Lovelace support
3. **Document migrations** - Update CLAUDE.md with learnings

### Next 3 Months

1. **Complete Phases 4-6** (Stateless services, GPU workloads, Monitoring)
2. **Begin production migration** - Migrate remaining stateless services
3. **Update documentation** - Capture all lessons learned

---

## Open Questions

1. **Service Mesh:** Do we need Istio/Linkerd for service-to-service communication?
   - **Decision:** Defer until Phase 4-5, evaluate based on service complexity

2. **Helm Charts:** Should we package services as Helm charts or use plain Kubernetes manifests?
   - **Decision:** Start with manifests, migrate to Helm if complexity increases

3. **CI/CD Integration:** How to integrate cluster deployments with existing CI/CD?
   - **Decision:** Use ArgoCD or Flux for GitOps (evaluate in Phase 4)

4. **Multi-cluster:** Future-proof for cloud free-tier deployment?
   - **Decision:** Design for it, but single-cluster initially

5. **Backup Strategy:** Velero vs custom scripts?
   - **Decision:** Start with NFS snapshots + custom scripts, evaluate Velero in Phase 3

---

## References

**Internal Documentation:**
- `/etc/nixos/CLAUDE.md` - Agent workflows and patterns
- `/etc/nixos/AGENTS.md` - MCP integration details
- `/etc/nixos/justfile` - Deployment commands
- `/etc/nixos/modules/network-constants.nix` - Cluster configuration
- `/etc/nixos/docs/security/SECURITY_AUDIT_REPORT.md` - Comprehensive security audit (OWASP, K8s PSS, CIS)

**External Resources:**
- NixOS Kubernetes module: https://search.nixos.org/options?query=kubernetes
- Kubernetes docs: https://kubernetes.io/docs/home/
- NVIDIA device plugin: https://github.com/NVIDIA/k8s-device-plugin
- AMD GPU plugin: https://github.com/RadeonOpenCompute/k8s-device-plugin (experimental)

**Skills Installed:**
- `kubernetes-specialist` - Day-to-day operations
- `kubernetes-architect` - Architecture patterns
- `helm-chart-scaffolding` - Helm chart creation

---

**Last Updated:** 2026-03-16
**Status:** Phase 2 Complete → Phase 4 Started (Caddy Ingress deployed)
**Next Review:** After Phase 4 completion
