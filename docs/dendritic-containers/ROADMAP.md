# Containerization Roadmap

**Generated:** 2026-02-08  
**For:** Reverb-OS Cluster Container Migration

---

## Overview

This roadmap outlines the step-by-step plan for migrating Reverb-OS MCP infrastructure to production-grade containerized deployment using Podman.

---

## Phase 1: MCP-NixOS Adoption (Week 1)

**Goal:** Replace 14 custom MCP servers with single production-grade server

**Tasks:**

### Week 1
- [ ] 1.1. Add MCP-NixOS input to flake.nix
- [ ] 1.2. Create dendritic/features/mcp-nixos.nix
- [ ] 1.3. Test MCP-NixOS locally on zephyr
- [ ] 1.4. Update OpenCode configuration to use MCP-NixOS
- [ ] 1.5. Verify all MCP tools work with new server
- [ ] 1.6. Create migration branch: `git checkout -b dendritic-migration`

**Expected Outcome:**
- 90% reduction in token usage (~9,000 tokens/hour)
- Zero maintenance (community-managed)
- Single package updates vs 14 packages
- Production-grade stdio MCP implementation

### Week 2
- [ ] 1.7. Remove 14 custom MCP npm packages
- [ ] 1.8. Remove custom Python MCP server
- [ ] 1.9. Remove legacy modules (mcp-servers.nix, mcp-server.nix)
- [ ] 2.0. Full rebuild and test on zephyr
- [ ] 2.1. Verify OpenCode integration
- [ ] 2.2. Document any migration issues

**Rollback Plan:**
```bash
# Quick rollback
git checkout main
sudo nixos-rebuild switch
```

---

## Phase 2: Podman Core Infrastructure (Week 2-3)

**Goal:** Establish Podman containerization platform

**Tasks:**

### Week 2
- [ ] 2.1. Add Quadlet-Nix input to flake.nix
- [ ] 2.2. Create dendritic/features/podman-core.nix
- [ ] 2.3. Create dendritic/nodes/zephyr/containers.nix
- [ ] 2.4. Test Podman enablement
- [ ] 2.5. Containerize MCP-NixOS
- [ ] 2.6. Test containerized MCP-NixOS

### Week 3
- [ ] 3.1. Add NVIDIA Container Toolkit support
- [ ] 3.2. Test GPU passthrough
- [ ] 3.3. Document Podman patterns for GPU workloads
- [ ] 3.4. Add health checks
- [ ] 3.5. Create container backup strategy
- [ ] 3.6. Test on all nodes

**Expected Outcome:**
- Container isolation for MCP services
- Easy updates: `podman pull` vs full rebuilds
- Resource limits per container
- Independent restart capability
- GPU passthrough for future workloads

---

## Phase 3: Nexus GPU Split Implementation (Week 4)

**Goal:** GPU 0 for SteamNix, GPU 1 for Mining

**Tasks:**

### Week 4
- [ ] 4.1. Find SteamNix container image
- [ ] 4.2. Create dendritic/features/podman-gpu-nvidia.nix
- [ ] 4.3. Create dendritic/nodes/nexus/containers.nix
- [ ] 4.4. Implement SteamNix container (GPU 0, 4K TV)
  - Resolution: 3840x2160
  - Refresh rate: 60Hz
  - No HDR
- [ ] 4.5. Configure lolminer for GPU 1 only
- [ ] 4.6. Test SteamNix (4K TV, auto-start)
- [ ] 4.7. Test mining on GPU 1
- [ ] 4.8. Deploy to nexus
- [ ] 4.9. Verify GPU isolation
- [ ] 4.10. Document SteamNix + Mining coordination

**Expected Outcome:**
- GPU 0 dedicated to gaming (no conflicts)
- GPU 1 dedicated to mining (higher power limit)
- Container isolation prevents cross-interference
- Independent start/stop per GPU workload

### Week 5
- [ ] 5.1. Test gaming + mining coordination
- [ ] 5.2. Implement auto-pause of mining during SteamNix
- [ ] 5.3. Add GPU monitoring
- [ ] 5.4. Deploy to forge (test multi-node patterns)
- [ ] 5.5. Test GPU split on forge

**Expected Outcome:**
- Working GPU split model
- Gaming and mining coexist without conflicts
- Production-grade GPU workload management
- Scalable to additional GPU nodes

---

## Phase 4: Cluster-Wide Deployment (Week 6+)

**Goal:** MCP-NixOS + Podman on all nodes

**Tasks:**

### Week 6
- [ ] 6.1. Deploy MCP-NixOS to nexus
- [ ] 6.2. Deploy MCP-NixOS to forge
- [ ] 6.3. Deploy MCP-NixOS to sentry
- [ ] 6.4. Test cluster-wide MCP access
- [ ] 6.5. Implement health monitoring
- [ ] 6.6. Add backup for containers
- [ ] 6.7. Document cluster-wide patterns
- [ ] 6.8. Train team on container operations
- [ ] 6.9. Establish update procedures

**Expected Outcome:**
- All nodes have consistent MCP access
- Reduced token costs (shared queries)
- Production-grade monitoring
- Zero-downtime deployment strategy

---

## Phase 5: Advanced Features (Week 8+)

**Goals:**
- Monitoring stack (Grafana + Prometheus)
- Rolling updates
- Secret management (SOPS or agenix)
- Multi-client coordination
- Performance optimization

**Research Areas:**
- [ ] 5.1. Monitoring stack patterns
- [ ] 5.2. Container orchestration
- [ ] 5.3. Backup strategies
- [ ] 5.4. Update automation
- [ ] 5.5. Multi-node scaling

**Tasks:**
- [ ] 5.X. Evaluate monitoring options
- [ ] 5.X. Choose monitoring stack
- [ ] 5.X. Implement Prometheus + Grafana
- [ ] 5.X. Create dashboards
- [ ] 5.X. Document metrics
- [ ] 5.X. Train team on monitoring

---

## zai-mcp-server Research (Defer Decision)

**Status:** Connected in OpenCode, implementation unknown

**Research Questions:**
- Where is the implementation located?
- Can it be containerized?
- Does it provide features not in mcp-nixos?
- What API endpoints does it expose?
- How does it integrate with OpenCode?

**Decision:** Defer until Phase 1 complete
- **Rationale:** Focus on MCP-NixOS first (highest ROI)
- **Contingency:** Can adopt zai-mcp-server after core migration

---

## Success Criteria

### Token Reduction Targets
- **Before:** ~10,000 tokens/hour (14 servers × 750 tokens)
- **After Phase 1:** ~1,000 tokens/hour (MCP-NixOS only)
- **After Phase 2:** ~1,000 tokens/hour (cluster-wide, shared queries)
- **After Phase 4:** ~500 tokens/hour (optimized queries)

### Maintenance Targets
- **Before:** 2-4 hours/week (manual npm updates)
- **After Phase 1:** 0 hours/week (community-maintained)
- **After Phase 2:** 0 hours/week (image pulls only)
- **After Phase 4:** 0 hours/week (automated checks)

### Containerization Metrics
- **Before:** 0 containers (all services on host)
- **After Phase 2:** 5+ containers (MCP, monitoring, etc.)
- **After Phase 4:** 10+ containers (per-node services)
- **After Phase 6:** 15+ containers (full homelab)

---

## Risk Mitigation

| Risk | Strategy |
|------|----------|
| Migration failure | Git branch, test before delete, rollback plan |
| Container bugs | Test thoroughly, use proven patterns (mcp-nixos) |
| GPU passthrough | Use `--userns=keep-id`, test isolation |
| Performance overhead | Monitor with Podman metrics, set resource limits |
| Data loss | Volume backups, snapshot before major changes |

---

## Timeline

- **Week 1:** MCP-NixOS adoption
- **Week 2-3:** Podman infrastructure
- **Week 4:** Nexus GPU split
- **Week 5-6:** Cluster-wide deployment
- **Week 7-8:** Advanced features

**Total Estimated Time:** 8 weeks for complete migration

---

## Dependencies & Research Areas

### Required Tools
```nix
environment.systemPackages = with pkgs; [
  podman
  podman-compose
  jq
  curl
  nvidia-container-toolkit  # For GPU passthrough
];
```

### External Resources
- mcp-nixos repository: https://github.com/utensils/mcp-nixos
- Quadlet-Nix repository: https://github.com/SEIAROTg/quadlet-nix
- Tarow/Nix-Podman-Stacks: https://github.com/Tarow/nix-podman-stacks
- Home Manager documentation: https://nix-community.github.io/home-manager
- NixOS wiki: https://wiki.nixos.org/wiki

---

**Last Updated:** 2026-02-08
