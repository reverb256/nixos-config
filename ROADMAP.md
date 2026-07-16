# NixOS Cluster Kubernetes Migration Roadmap

**Status:** K3s migration COMPLETE (Phase 1-7) — Sovereign Service Mesh OPERATIONAL — Post-migration hardening in progress
**Created:** 2026-03-08 | **Owner:** j_kro | **Last Updated:** 2026-05-23 (stale — see INFRASTRUCTURE-AUDIT.md for current state)

> **See `INFRASTRUCTURE-AUDIT.md` for current cluster state, issues, and next steps.**
> **See `docs/plans/2026-05-01-mcp-system-plan.md` for MCP system plan.**
> **See `docs/SOVEREIGN-SERVICE-MESH-STATUS.md` for AI Gateway mesh status.**

## Current State (2026-05-02)

**What changed since last update:**
- All K8s nodes now show `Ready` (was `Unknown`)
- Grafana K8s OAuth fixed (duplicated env vars removed, correct Casdoor endpoints)
- Grafana admin-secret namespace fixed (was `ai-inference`, now `monitoring`)
- K8s oauth2-proxy sidecars removed from haven, kagent, mission-control (centralized SSO via Caddy)
- Alert-webhook stub removed (AlertManager logs via Alloy → Loki)
- Privacy-filter NetworkPolicy fixed (allows AI gateway traffic)
- 60 pods running across 22 namespaces, all nodes healthy

**Known stubs needing real implementation:**
- Knowledge Fabric API: inline Python stub, needs Qdrant embedding pipeline
- Privacy filter: `pip install` at runtime, needs proper container image
- Gaming detection: `sleep infinity`, real detection runs on host via systemd
- nix-csi: empty module, hostPath volumes used directly

**Confirmed permanent:** TurboQuant llama.cpp on 3090 (24.7 tok/s). No vLLM on 3090.
**Z.AI API ~Jul 8** (2-month free extension from Z.AI, was May 8)

> **Historical content below preserved for reference. Many sections are stale (service inventory, `services.kubernetes` references, timeline estimates). Rely on `INFRASTRUCTURE-AUDIT.md` for current state.**

## Executive Summary

**Objective:** Migrate all containerizable services from NixOS systemd to Kubernetes across a 4-node cluster (Zephyr, Nexus, Forge, Sentry).

**Implementation:** Migration was completed using **K3s** (v1.34.5) via NixOS `services.k3s` module, replacing the original plan to use `services.kubernetes`. K3s was chosen for its simpler operational model (single binary, embedded etcd, auto-TLS) while maintaining full Kubernetes API compatibility.

> **Note:** This document originally described a full `services.kubernetes` deployment. The cluster now runs K3s. See the [K3s Migration Audit](#k3s-migration-audit) section below for the current state and remaining work.

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

**AI/ML Services (4):**
- AI Inference Gateway (OpenAI-compatible API)
- llama.cpp / TurboQuant (local LLM on 3090)
- LM Studio (desktop UI)
- Whisper Dictation (speech-to-text)

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

**CNI:** Flannel VXLAN (default K3s)
- Network: `10.244.0.0/16`
- Backend: VXLAN (UDP 8472)
- MTU: 1450 (VXLAN overhead)
- Note: Calico migration was planned but not deployed

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

### Phase 1: Foundation (Week 1-2) COMPLETE

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
     # Networking (Calico CNI)
     flannel.enable = false;  # Disabled after Calico migration
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
   - ✅ `kubectl get pods --all-namespaces` - CoreDNS, Calico running
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

> **Phase 3 (DB Migration): DEFERRED** — databases handled as K8s StatefulSets, no separate phase needed.

---

### Phase 4: Stateless Services COMPLETE (subset) (Week 4-6)

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
- llama.cpp / TurboQuant
- LM Studio (desktop app, may stay external)
- Whisper Dictation

**Tier 4 - Utilities (Week 6):**
- ✅ SearXNG **MIGRATED (2026-03-19)**
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
- Services can communicate (ai-inference → llama.cpp, etc.)
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
- **llama.cpp / TurboQuant** - GPU inference (permanent on 3090)
- **Whisper Dictation** - Single GPU

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
- ✅ GPU workload manifests (llama.cpp, TurboQuant)
- ✅ Scheduling strategies documented
- ✅ AI Gateway integrated with Kubernetes service
- ✅ End-to-end testing complete (17/18 tests passed)

**Phase 5 Status: ✅ COMPLETE (95%)** - Completed 2026-03-19

**Achievements:**
- ✅ llama.cpp deployed via external service integration
- ✅ Kubernetes service configured (llama-cpp-qwen.ai-inference.svc.cluster.local:8080)
- ✅ AI Gateway integration verified
- ✅ GPU resources allocated (RTX 3060 Ti: 1331 MiB, RTX 3090: 2726 MiB)
- ✅ Comprehensive test suite executed (E2E-TEST-REPORT.md)
- ✅ Model: Qwen3.5-2B-IQ4_NL.gguf with Flash Attention + bf16 KV cache
- ✅ 3090: TurboQuant llama.cpp permanent (24.7 tok/s)
- GPU monitoring deployed

**Known Issues:**
- ❌ Forge GPU registration failing (RTX 4060 Ada Lovelace support issue)

---

> **Status:** PARTIALLY COMPLETE. Alloy 4/4 DaemonSet, Prometheus, Grafana, Loki, Mimir, Tempo all running. prometheus-adapter fixed. AlertManager not configured. Alerting rules not configured.

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

> **Status:** IN PROGRESS. Some systemd services migrated to K8s (llama-servers, redis). Many still dual-running.

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
- **Mitigation:** Calico is well-tested with enterprise features
  - BGP routing provides dynamic pod CIDR distribution
  - IPVS load balancing improves performance (O(1) vs O(n))
  - WireGuard encryption secures pod-to-pod traffic
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
- Bidders: Mining (baseline), Kubernetes (AI workloads), Gaming (priority override)
- Prometheus metrics on port 9200
- Auto-scales mining based on cluster demand

**Documentation:** `modules/compute-market/default.nix`, `docs/compute-market.md`

---

## Next Steps

### Immediate (This Week)

1. ✅ **Test storage classes** - PVC creation verified (qdrant operational)
2. ✅ **Complete Phase 3** - GlitchTip PostgreSQL migrated
3. ✅ **Commit updated documentation** - STATUS.md, ROADMAP.md changes

### This Month

1. ✅ **Complete Phase 3** (Stateful Services - GlitchTip DB, Nextcloud)
2. ✅ **Investigate Forge GPU** - RTX 4060 Ada Lovelace support
3. ✅ **Document migrations** - Update CLAUDE.md with learnings

### Next 3 Months

1. ✅ **Complete Phases 4-6** (Stateless services, GPU workloads, Monitoring)
2. ✅ **Begin production migration** - Migrate remaining stateless services
3. ✅ **Update documentation** - Capture all lessons learned

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

## AI Stack Improvements (Phase 5)

### Objectives
- Enhance observability with Loki/Tempo stack
- Implement MLflow model registry for Qwen3.5 models
- Optimize GPU workload coordination between mining and Kubernetes
- Improve multi-modal model serving capabilities
- Deploy advanced caching strategies
- Implement zero-trust security model
- Expand MCP server ecosystem

### Completed Quick Fixes (2026-03-18)
- ✅ Sentry: Enabled lolminer-amd for RX 5600 XT GPU mining
- ✅ Zephyr: Fixed Redis port conflict (changed to 6380)
- ✅ All hosts: Fixed hermes-agent systemd ordering dependencies
- ✅ All hosts: Fixed flake-lock-sync systemd ordering dependencies

### Implementation Plan

| Feature | Priority | Est. Time | Dependencies | Status |
|----------|-----------|------------|---------------|---------|
| Sentry lolminer-amd | P0 | 15 min | None | ✅ Done |
| Redis port conflict | P0 | 10 min | None | ✅ Done |
| Systemd ordering fixes | P0 | 10 min | None | ✅ Done |
| Unified Redis service | P1 | 1 hr | Port conflict fix | 📋 Planning |
| MLflow integration | P2 | 4-6 hr | Unified Redis | 📋 Planning |
| Loki/Tempo stack | P2 | 4-6 hr | Systemd hardening | 📋 Planning |
| GPU workload optimization | P2 | 6-8 hr | Basic fixes | 📋 Planning |
| Multi-modal serving | P2 | 8-12 hr | MLflow integration | 📋 Planning |
| Advanced caching | P3 | 4-6 hr | Unified Redis | 📋 Planning |
| Zero-trust security | P3 | 6-8 hr | Observability + multi-modal | 📋 Planning |
| MCP ecosystem | P3 | 4-8 hr | Zero-trust security | 📋 Planning |

### Key Improvements Detail

#### 1. MLflow Model Registry
- Track Qwen3.5 model experiments, versions, and metadata
- Store model artifacts on NFS (/mnt/garage/mlflow)
- Integrate with AI Gateway for inference logging

#### 2. Loki/Tempo Observability
- Add Loki for log aggregation
- Add Tempo for distributed tracing
- Integrate with existing Grafana dashboards

#### 3. GPU Workload Optimization
- Coordinate mining vs Kubernetes GPU workloads
- Implement GPU preemption for critical workloads
- Add GPU utilization dashboards

#### 4. Multi-Modal Serving
- Enhance AI Gateway with vision/audio support
- Integrate CLIP for image understanding
- Add Whisper STT endpoints

#### 5. Advanced Caching
- Cache warming for common queries
- Cache eviction strategies (LFU)
- Cache analytics dashboard

#### 6. Zero-Trust Security
- Service mesh with mTLS
- Fine-grained RBAC
- Request signing

#### 7. MCP Ecosystem
- MCP discovery protocol
- MCP marketplace
- MCP deployment automation

### Skills Available
- `mlops-engineer` - Full ML lifecycle management
- `machine-learning-engineer` - Model deployment and serving

---

## Sovereign Service Mesh (2026-04-24)

### Overview

**Status:** ✅ OPERATIONAL — Phase 1 Complete

The Sovereign Service Mesh is a bus-style architecture where the AI Gateway serves as the central orchestrator for all AI/ML workloads. The gateway implements RRF (Reciprocal Rank Fusion) middleware that combines:

- **Qdrant** — Vector database for semantic search
- **SearXNG** — Web search for current information
- **QueryIntent routing** — Automatic query classification
- **CrossEncoder reranking** — Result quality optimization

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                       AI GATEWAY (Central Bus)                       │
│                   ClusterIP: 10.15.67.242:8080                       │
├─────────────────────────────────────────────────────────────────────┤
│  /search/hybrid  ←→  SearXNG + Qdrant with RRF fusion               │
│  /rag/search      ←→  Qdrant semantic search                         │
│  /v1/embeddings   ←→  BGE-M3 embedding generation                    │
│  /v1/chat/*       ←→  Model routing (Qwen3.6, SGemma, Qwen3.5)       │
│                                                                         │
│  MIDDLEWARE:                                                            │
│  • Knowledge Fabric (RRF K=60)                                         │
│  • QueryIntent routing (REALTIME/CODE/FACTUAL/PROCEDURAL)            │
│  • CrossEncoder reranking                                              │
└──────────────┬────────────────────────────────────────────────────────┘
               │
     ┌─────────┼─────────┐
     │         │         │
┌────▼─────┐ ┌▼──────┐ ┌▼────────┐
│  HERMES  │ │  OMP   │ │  CRON   │
│  (agent) │ │(coding)│ │(scheduled)
└──────────┘ └───────┘ └─────────┘
     │         │         │
     └─────────┴─────────┘
               │
    ┌──────────┴──────────┐
    │                     │
┌───▼────┐          ┌────▼───┐
│ Qdrant │          │ SearXNG│
│(vector)│          │ (web)  │
└────────┘          └────────┘
```

### Mesh Components

| Component | Status | ClusterIP | Node | Purpose |
|-----------|--------|-----------|------|---------|
| AI Gateway | ✅ Running | 10.15.67.242:8080 | nexus | Central bus with RRF middleware |
| Qdrant | ✅ Running | 10.5.93.32:6333 | nexus | Vector database (v1.13.4) |
| Knowledge Fabric API | ✅ Running | 10.6.31.109:3000 | nexus | Stub API (RRF in gateway) |
| SearXNG | ✅ Running | 10.4.98.141:8080 | nexus | Web search (v2026.4.17) |
| Valkey | ✅ Running | — | nexus | Redis-compatible cache |
| Redis | ✅ Running | 10.10.99.29:6379 | nexus | Gateway cache |

### Implementation Phases

#### Phase 0: Kill pi (2-3h)
- [ ] Audit pi-unique extensions
- [ ] Port knowledge-fabric out of pi
- [ ] Remove pi from NixOS
- [ ] Archive ~/.pi/

#### Phase 1: Gateway Unified Endpoints (4-6h)
- [x] AI Gateway deployed with RRF middleware
- [x] Qdrant + SearXNG integration
- [ ] `/v1/search` — Unified search wrapper
- [ ] `/v1/knowledge/commit` — Knowledge upsert
- [ ] `/v1/knowledge/query` — Qdrant wrapper
- [ ] `/v1/chat/smol|slow|plan` — Model role routes

#### Phase 2: Wire Hermes Through Mesh (2-3h)
- [x] Update Hermes config to use gateway
- [ ] Hermes memory → gateway dual-write
- [ ] Hermes brain queries → gateway

#### Phase 3: Collapse Per-Tool Configs (3-4h)
- [ ] omp → gateway only
- [ ] Harvest opencode, deprecate
- [ ] Verify mesh exclusivity

### Documentation

- **Sovereign Service Mesh Plan:** `/etc/nixos/.hermes/plans/2026-04-22_sovereign-service-mesh.md`
- **Service Mesh Status:** `/etc/nixos/docs/SOVEREIGN-SERVICE-MESH-STATUS.md`
- **Knowledge Fabric Reflow:** `/etc/nixos/docs/KNOWLEDGE-FABRIC-REFLOW.md`

---

## K3s Migration Audit (2026-04-07)

### Current Cluster State

| Component | Status |
|-----------|--------|
| K3s version | v1.34.5+k3s1 |
| Nodes | 4/4 functional (zephyr, nexus, forge, sentry) |
| etcd HA | 3-node quorum (nexus=bootstrap, zephyr, sentry) |
| VIP (Keepalived) | 10.1.1.100 ✅ |
| CNI | Flannel VXLAN (UDP 8472) — default K3s CNI |
| Ingress | Caddy (ingress-system namespace) |
| GPU devices | 5 NVIDIA registered (forge=2, nexus=1, zephyr=2) |
| Storage | local-path provisioner (default) |

### Completed Fixes (2026-04-07)

| # | Fix | Status |
|---|-----|--------|
| 1 | Fixed `oom-protection.nix` dead kubelet reference → protect k3s.service | ✅ |
| 2 | Fixed `serverAddr` inconsistency — all nodes now use VIP (10.1.1.100) | ✅ (needs deploy) |
| 3 | Added `clusterInit = true` to nexus (bootstrap node) | ✅ (needs deploy) |
| 4 | Removed dead Flannel UDP 8472 ports from all node profiles | ✅ (needs deploy) |
| 5 | Added `iptables` to k3s-cluster systemPackages for Calico compat | ✅ (needs deploy) |
| 6 | Added `--kube-proxy-arg=iptables-backend=nft` for Calico nft compat | ✅ (needs deploy) |
| 7 | Deleted orphaned `autoresearch` and `caddy-ingress` namespaces | ✅ |
| 8 | Applied PSS labels to all user namespaces | ✅ |
| 9 | Pinned `:latest` image tags to SHA256 digests | ✅ |
| 10 | Created default-deny network policies (mining, ai-inference, search) | ✅ |
| 11 | Scaled down gpu-miner-nexus (GPU contention with desktop) | ✅ |
| 12 | Updated ROADMAP.md to reflect K3s migration | ✅ |

### Open Issues (Require Deploy)

| # | Issue | Resolution |
|---|-------|----------|
| 1 | **Calico CNI broken on server nodes** — nftables segfault + nat table conflict | Deploy `k3s-cluster.nix` changes (iptables pkg + kube-proxy-arg). If still broken, switch to Flannel (k3s default). |
| 2 | **Sentry metrics-server unknown** — depends on Calico fix | Will resolve when CNI is healthy. |
| 3 | **Nexus GPU contention** — desktop + lolMiner consuming GPU, K8s can't allocate | Decide: mine via K8s only (disable host lolMiner) or accept desktop GPU is unavailable. |

### Future Improvements

- Migrate Prometheus/Grafana from systemd to K8s
- Add NFS-backed storage classes (fast-local-ssd, large-nfs-storage)
- Implement GitOps (ArgoCD/Flux) for manifest management
- Add Velero for backup/restore
- Deploy resource quotas per namespace
- Add HPA/VPA for auto-scaling

---

**Last Updated:** 2026-04-24
**Status:** K3s migration COMPLETE (Phase 1-5) — Post-migration hardening + cleanup in progress (Phase 6-7)

---

## 2026-04-24 Audit Notes (Stale Items)

The following items in this roadmap are stale and no longer reflect current infrastructure:
- Service inventory (lines 45-82): Lists 31 services including GlitchTip, Nextcloud, Bolt.diy, LM Studio, Whisper, Stability Matrix — most not deployed or unused
- CNI listed as Calico: Cluster actually runs K3s with flannel VXLAN
- Timeline Week 1-9: Cluster has been running 19+ days past initial K3s deploy
- NVIDIA device plugin Forge 0 GPUs: Forge now has NVIDIA GPUs registered

Current verified state: See `infrastructure-docs/` for the 2026-04-24 audit notes (the `~/brain/` vault was retired during the 2026-07-16 workspace cleanup).
