# Colmena + x86-64-v3 Optimization + Kubernetes Integration Design

**Status:** Design Approved | **Created:** 2026-03-09 | **Owner:** j_kro
**Related:** [Kubernetes Migration Roadmap](../../ROADMAP.md)

---

## Executive Summary

**Objective:** Enhance NixOS cluster management with Colmena deployment tool, x86-64-v3 CPU microarchitecture optimizations, and Kubernetes-aware deployment patterns.

**Goals:**
1. Enable selective deployment via node tags (control plane, workers, storage, GPU)
2. Optimize each node for its specific CPU microarchitecture (znver3, znver2, skylake, znver1)
3. Enable distributed builds across 4-node cluster (42 cores total)
4. Support Kubernetes migration with safe rolling updates
5. Maintain backward compatibility with existing workflows

**Timeline:** 1-2 weeks implementation (foundation for 9-week K8s migration)

---

## Table of Contents

1. [Overall Architecture](#1-overall-architecture)
2. [Flake Structure Changes](#2-flake-structure-changes)
3. [Node Tagging & Deployment Config](#3-node-tagging--deployment-config)
4. [Distributed Builds Configuration](#4-distributed-builds-configuration)
5. [Rolling Update Workflow](#5-rolling-update-workflow)
6. [Testing & Validation Strategy](#6-testing--validation-strategy)
7. [Migration Path & Rollout Plan](#7-migration-path--rollout-plan)
8. [File Structure & Summary](#8-file-structure--summary)
9. [Kubernetes Integration](#9-kubernetes-integration)

---

## 1. Overall Architecture

### High-Level Structure

```
flake.nix
├── Outputs: colmenaHive (using colmena.lib.makeHive)
├── colmena.nix
│   ├── meta
│   │   ├── nixpkgs (baseline, shared)
│   │   ├── nodeNixpkgs (CPU-tuned instances per node)
│   │   ├── machinesFile (distributed build farm)
│   │   └── specialArgs (inputs, self)
│   ├── defaults (shared modules)
│   └── nodes
│       ├── zephyr (targetHost=null, allowLocalDeployment, tags=[control-plane, k8s-master])
│       ├── nexus (targetHost=10.1.1.120, tags=[storage, k8s-storage, nvidia-gpu])
│       ├── forge (targetHost=10.1.1.130, tags=[gpu, compute, k8s-gpu-mixed])
│       └── sentry (targetHost=10.1.1.140, tags=[monitoring, k8s-gpu-amd])
└── machines.nix (4-node build farm: zephyr, nexus, forge, sentry)
```

### Key Design Decisions

1. **Single source of truth**: `colmena.nix` replaces current flake.nix host definitions
2. **CPU tuning in meta.nodeNixpkgs**: Provides tuned nixpkgs instances per node
3. **Tags for deployment flexibility**: Logical groupings (role-based + K8s-aware)
4. **Distributed builds**: All 4 nodes participate (42 cores total), conservative allocations for K8s workloads
5. **Rolling updates**: Justfile orchestrates sequential deployment with validation gates
6. **K8s integration**: Tags and build priorities respect K8s control plane stability needs

### Data Flow During Deployment

1. User runs `just deploy` or `just deploy-tag @<tag>`
2. Colmena builds closures with CPU-tuned nixpkgs (`nodeNixpkgs`)
3. Distributed builds forward to available builders (machines.nix)
4. `colmena apply --dry-run` shows what changes
5. User approves, Colmena activates on target node
6. K8s health checks validate cluster components
7. Next node in sequence deploys only after previous succeeds

---

## 2. Flake Structure Changes

### Current flake.nix Outputs

```nix
outputs = inputs @ {...}: {
  apps.x86_64-linux.colmena = ...;
  devShells.x86_64-linux.default = ...;
}
```

### Proposed Changes

```nix
outputs = inputs @ {self, nixpkgs, colmena, ...}: {
  # NEW: Colmena hive output
  colmenaHive = colmena.lib.makeHive {
    import ./colmena.nix inputs;
  };

  # KEEP: Existing apps (they work with colmenaHive)
  apps.x86_64-linux.colmena = ...;

  # KEEP: Existing devshells
  devShells.x86_64-linux.default = ...;
}
```

### Updated colmena.nix Structure

```nix
{
  inputs,
  self,
}: let
  # CPU-tuned nixpkgs instances
  tunedNixpkgs = system: microarch: import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (self: super: {
        stdenv = super.stdenv // {
          hostPlatform = super.stdenv.hostPlatform // {
            gcc.arch = microarch;  # "znver3", "znver2", "skylake", "znver1"
          };
        };
      })
    ];
  };
in {
  meta = {
    # Baseline (required by Colmena, but unused due to nodeNixpkgs)
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    # NEW: Per-node CPU tuning
    nodeNixpkgs = {
      zephyr = tunedNixpkgs "x86_64-linux" "znver3";  # Ryzen 9 5950X (Zen 3)
      nexus = tunedNixpkgs "x86_64-linux" "znver2";    # Ryzen 9 3900X (Zen 2)
      forge = tunedNixpkgs "x86_64-linux" "skylake";    # i5-9500 (Coffee Lake)
      sentry = tunedNixpkgs "x86_64-linux" "znver1";   # Ryzen 7 1700 (Zen 1)
    };

    # NEW: Distributed builds (all 4 nodes)
    machinesFile = ./machines.nix;

    specialArgs = {inherit inputs self;};
  };

  # ... nodes configuration (see Section 3)
}
```

### Why This Approach?

- **Explicit CPU tuning**: Each node gets `-march` flags appropriate for its CPU
- **No binary cache sharing for system packages**: Each node builds unique closure (acceptable trade-off for maximum optimization)
- **Leverages existing flake structure**: Builds on current patterns, minimal disruption

---

## 3. Node Tagging & Deployment Config

### Tag Taxonomy for Cluster

```nix
{
  # Zephyr - Control plane (local deployment)
  zephyr = {
    deployment = {
      targetHost = null;  # No SSH
      allowLocalDeployment = true;
      tags = [
        "control-plane"      # Legacy NixOS role
        "k8s-master"        # K8s control plane
        "k8s-node"          # Also runs workloads
        "local"
      ];
    };
  };

  # Nexus - Storage node + K8s storage worker
  nexus = {
    deployment = {
      targetHost = "10.1.1.120";
      targetUser = "j_kro";
      tags = [
        "storage"           # Legacy role
        "k8s-worker"        # K8s worker
        "k8s-storage"       # PVC storage provider
        "nvidia-gpu"        # Has 1x RTX 3060 Ti
        "remote"
      ];
    };
  };

  # Forge - GPU/compute + K8s multi-GPU worker
  forge = {
    deployment = {
      targetHost = "10.1.1.130";
      targetUser = "j_kro";
      tags = [
        "gpu"               # Legacy role
        "compute"           # Legacy role
        "k8s-worker"        # K8s GPU worker
        "k8s-gpu-mixed"     # Both NVIDIA (2x) + AMD (2x)
        "remote"
      ];
    };
  };

  # Sentry - Monitoring + K8s AMD GPU worker
  sentry = {
    deployment = {
      targetHost = "10.1.1.140";
      targetUser = "j_kro";
      tags = [
        "monitoring"        # Legacy role
        "k8s-worker"        # K8s monitoring worker
        "k8s-gpu-amd"       # Has 1x RX 5600 XT
        "remote"
      ];
    };
  };
}
```

### Deployment Patterns Enabled

```bash
# Deploy to all remote nodes (nexus, forge, sentry)
colmena apply --on @remote

# Deploy to K8s control plane only (zephyr)
colmena apply --on @k8s-master

# Deploy to all K8s workers
colmena apply --on @k8s-worker

# Deploy to storage + monitoring (infra stack)
colmena apply --on @storage,@monitoring

# Deploy to K8s storage workers only
colmena apply --on @k8s-storage

# Deploy to GPU nodes (NVIDIA or mixed)
colmena apply --on @nvidia-gpu,@k8s-gpu-mixed

# Deploy to all lab infrastructure
colmena apply --on @infra-lab  # (if we add this tag)

# Test locally before pushing
colmena apply-local --on @control-plane
```

### Updated mkHost Helper

```nix
mkHost = {
  hostName,
  targetHost,
  tags ? [],
}: {...}: {
  deployment = {
    inherit targetHost;
    targetUser = "j_kro";
    inherit tags;
    allowLocalDeployment = if targetHost == null then true else false;
  };
  # ... rest of host config
};
```

---

## 4. Distributed Builds Configuration

### machines.nix (All 4 Nodes Participate)

**Total cluster: 42 cores (16 + 12 + 6 + 8)**

```nix
# Nix distributed build farm configuration
# Documentation: https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html
[
  # Zephyr - K8s control plane + node (16 cores, must stay stable)
  {
    hostName = "zephyr";
    systems = ["x86_64-linux"];
    sshUser = "j_kro";
    maxJobs = 8;  # CONSERVATIVE - apiserver/etcd need CPU
    speedFactor = 8;  # Fast, but not prioritized over K8s
    supportedFeatures = ["kvm" "big-parallel"];
    mandatoryFeatures = [];  # Don't force builds if K8s is busy
  }

  # Nexus - K8s storage worker + NFS (12 cores, needs I/O headroom)
  {
    hostName = "nexus";
    systems = ["x86_64-linux"];
    sshUser = "j_kro";
    maxJobs = 6;  # MODERATE - leave cores for NFS/PVC operations
    speedFactor = 5;
    supportedFeatures = ["big-parallel"];
  }

  # Forge - K8s multi-GPU worker (6 cores, MIXED NVIDIA/AMD)
  {
    hostName = "forge";
    systems = ["x86_64-linux"];
    sshUser = "j_kro";
    maxJobs = 2;  # MINIMAL - GPU pods need CPU, mixed vendor = chaos
    speedFactor = 2;  # Deprioritized - GPUs matter more than builds
    supportedFeatures = ["kvm"];  # No big-parallel - keep resources for GPU
  }

  # Sentry - K8s monitoring worker (8 cores)
  {
    hostName = "sentry";
    systems = ["x86_64-linux"];
    sshUser = "j_kro";
    maxJobs = 4;  # LIGHT - Prometheus/Grafana/Loki need CPU
    speedFactor = 4;
    supportedFeatures = ["big-parallel"];
  }
]
```

### Build Priority Order

1. **Zephyr** (speedFactor 8, maxJobs 8) - Primary builder when K8s is idle
2. **Nexus** (speedFactor 5, maxJobs 6) - Secondary builder
3. **Sentry** (speedFactor 4, maxJobs 4) - Moderate capacity
4. **Forge** (speedFactor 2, maxJobs 2) - Lowest priority, GPU-focused

**Load-based distribution**: Nix automatically sends more builds to Zephyr (speedFactor 8) than Forge (speedFactor 2) based on relative performance.

### Prerequisites

1. **SSH key setup**: Passwordless SSH from all nodes to all nodes for `j_kro` user
2. **Trusted users**: All nodes need `j_kro` in `nix.settings.trusted-users`
3. **Verification**:
   ```bash
   # Test SSH connectivity
   for host in nexus forge sentry; do
     ssh $host "hostname"
   done

   # Verify distributed builds work
   nix-build -E 'with import <nixpkgs> {}; hello' --max-jobs 20
   nix-store --query --builder /nix/store/*-hello
   ```

---

## 5. Rolling Update Workflow

### Fully Automated Rolling Update

**Updated justfile with K8s-aware sequence:**

```nix
deploy-v3-rolling:
    #!/usr/bin/env bash
    set -e  # Stop on any error
    source {{JUST_HELPERS}}

    _header "v3 Rolling Update → All Nodes (K8s-Aware Order)"

    # Step 1: Pre-flight validation - build all closures
    _step "building closures for all nodes..."
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- build
    _done "all closures built successfully"

    # Step 2: Deploy to Zephyr (K8s control plane, local)
    _step "deploying → zephyr (k8s-master)"
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply-local --on zephyr
    _step "validating K8s control plane..."
    ssh zephyr "kubectl get nodes"
    ssh zephyr "systemctl status apiserver etcd kubelet" || true
    _done "zephyr updated to v3, K8s control plane healthy"

    # Step 3: Deploy to remote workers sequentially (K8s order)
    _step "deploying → k8s workers"
    for host in sentry nexus forge; do
        cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on $host --verbose
        _step "validating $host..."
        ssh $host "kubectl get nodes | grep $host"
        ssh $host "systemctl status kubelet" || true
        _done "$host updated to v3"
    done

    _time; _header "all nodes updated to v3 successfully"

# Deploy by tag (parallel deployment)
deploy-tag ARG:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _header "deploy → @{{ARG}} (parallel)"
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on @{{ARG}} --verbose
    _done "nodes with tag @{{ARG}} updated"

# Emergency rollback
rollback ARG:
    #!/usr/bin/env bash
    _header "rollback → {{ARG}}"
    ssh {{ARG}} "sudo nixos-rebuild rollback"
    _done "{{ARG}} rolled back to previous generation"
```

### Why This Order?

**K8s best practices** (from official docs): "Upgrade control plane first, then workers"

1. **Zephyr** (k8s-master) - Control plane must stay available
2. **Sentry** (monitoring) - Verify observability before other workers
3. **Nexus** (storage) - Verify PVCs/storage still accessible
4. **Forge** (GPU/mixed) - Most complex, highest risk

### Error Handling

- `set -e` ensures deployment stops immediately if any node fails
- Failed nodes stay on previous working generation
- Manual rollback: `just rollback <node>`
- Quick cluster health check: `kubectl get nodes`

---

## 6. Testing & Validation Strategy

### Pre-Deployment Validation

```bash
# 1. Verify flake is valid
nix flake check

# 2. Show what will be deployed
nix run .#apps.x86_64-linux.colmena -- eval --expr '{ nodes, ... }:
  builtins.mapAttrs (n: v: {
    cpu = v.config.nixpkgs.hostPlatform.gcc.arch or "default";
    tags = v.config.deployment.tags or [];
  }) nodes'

# 3. Build all closures without activating
nix run .#apps.x86_64-linux.colmena -- build

# 4. Dry-run on specific node
nix run .#apps.x86_64-linux.colmena -- apply --dry-run --on nexus

# 5. Verify distributed builds reachable
for host in forge nexus sentry; do
  ssh $host "nix-store --verify"
done
```

### Per-Node Validation After Deployment

```bash
# Verify CPU optimizations active
ssh <node> "nix-shell -p coreutils --run 'nix-store -q --requisites /run/current-system | head -20'"

# Check generation booted successfully
ssh <node> "nixos-rebuild list-generations"

# Verify services running
ssh <node> "systemctl --failed"

# For GPU nodes specifically
ssh forge "nvidia-smi"

# For K8s nodes
ssh <node> "kubectl get nodes"
ssh <node> "systemctl status kubelet"
```

### K8s-Specific Validation

```bash
# After deploying to Zephyr (control plane)
ssh zephyr "kubectl get nodes"
ssh zephyr "kubectl get pods --all-namespaces"
ssh zephyr "systemctl status apiserver etcd kubelet"

# After deploying to workers
for host in nexus forge sentry; do
  echo "=== $host ==="
  ssh $host "kubectl get nodes | grep $host"
  ssh $host "systemctl status kubelet"
done

# For GPU workers
ssh forge "kubectl describe node | grep -A10 'Allocated resources'"
ssh nexus "nvidia-smi"
```

---

## 7. Migration Path & Rollout Plan

### Phase 1: Preparation (Non-Breaking)

**Duration:** 1 day

```bash
# 1. Create feature branch
git checkout -b feature/colmena-v3-k8s-integration

# 2. Add new files (non-breaking)
touch machines.nix
# Edit flake.nix to add colmenaHive output (keep existing)
# Edit colmena.nix to add tags, nodeNixpkgs (keep existing structure)

# 3. Verify everything still works
nix flake check
just deploy --dry-run  # Existing command still works
```

### Phase 2: CPU Tuning Implementation

**Duration:** 1 day

```nix
# Edit flake.nix - add colmenaHive output
outputs = inputs @ {self, nixpkgs, colmena, ...}: {
  colmenaHive = colmena.lib.makeHive {
    import ./colmena.nix inputs;
  };
  # ... existing outputs
};

# Edit colmena.nix - add nodeNixpkgs with CPU tuning
# (See Section 2 for exact implementation)
```

### Phase 3: Distributed Build Setup

**Duration:** 1 day

```bash
# 1. Create machines.nix
# (See Section 4 for exact implementation)

# 2. Configure trusted users on all nodes
# Add to modules/common-host-defaults.nix:
nix.settings.trusted-users = ["j_kro"];

# 3. Test SSH connectivity between all nodes
for host in nexus forge sentry; do
  ssh $host "hostname"
done

# 4. Verify distributed builds work
nix-build -E 'with import <nixpkgs> {}; hello' --max-jobs 20
nix-store --query --builder /nix/store/*-hello  # Should show remote builder
```

### Phase 4: Gradual v3 Rollout (Sequential)

**Duration:** 1 day

```bash
# Step 1: Zephyr (local, safest)
just deploy-v3-rolling  # Stops after zephyr if error
# If fails: sudo nixos-rebuild rollback (local)

# Step 2: Sentry (monitoring, verify observability)
# Verify: kubectl get nodes, systemctl status prometheus

# Step 3: Nexus (storage)
# Verify: kubectl get nodes, mountpoint -q /data

# Step 4: Forge (GPU node, most complex)
# Verify: kubectl get nodes, nvidia-smi, GPU services
```

### Phase 5: Validation & Documentation

**Duration:** 1 day

```bash
# 1. Verify all nodes on correct generation
for host in zephyr nexus forge sentry; do
  echo "=== $host ==="
  ssh $host "nixos-rebuild list-generations | head -3"
  ssh $host "nixos-version"
done

# 2. Run integration tests
for host in zephyr nexus forge sentry; do
  ssh $host "systemctl --failed"
done

# 3. Test K8s cluster health
kubectl get nodes
kubectl get pods --all-namespaces

# 4. Update documentation
# - CLAUDE.md with new deployment patterns
# - AGENTS.md with Colmena workflows
```

### Phase 6: Merge & Cleanup

**Duration:** 1 day

```bash
# 1. Commit all changes
git add .
git commit -m "feat: add Colmena + x86-64-v3 + K8s-aware deployment

- Add per-node CPU tuning (znver3, znver2, skylake, znver1)
- Enable distributed builds across 4-node cluster (42 cores)
- Add K8s-aware node tags (k8s-master, k8s-worker, k8s-storage, k8s-gpu-*)
- Add automated rolling update workflow (K8s-safe order)
- Conservative build allocations for K8s workloads
- Foundation for K8s migration (ROADMAP.md Phase 0)"

# 2. Merge to main
git checkout main
git merge feature/colmena-v3-k8s-integration

# 3. Deploy final version
just deploy-v3-rolling
```

### Rollback Plan

```bash
# Quick rollback to pre-v3 generation
for host in nexus forge sentry; do
  ssh $host "sudo nixos-rebuild rollback"
done
# Zephyr (local)
sudo nixos-rebuild rollback

# Or rollback to specific generation
ssh <host> "nixos-rebuild switch --install <previous-generation-path>"
```

---

## 8. File Structure & Summary

### New Files

```
/etc/nixos/
├── machines.nix                                         # NEW
└── docs/plans/
    └── 2026-03-09-colmena-v3-k8s-integration-design.md  # NEW (this file)
```

### Files to Modify

```
/etc/nixos/
├── flake.nix                       # ADD: colmenaHive output
├── colmena.nix                     # MODIFY: Add nodeNixpkgs, tags, machinesFile
├── justfile                        # ADD: deploy-v3-rolling, deploy-tag, rollback
└── modules/
    └── common-host-defaults.nix    # MODIFY: Add j_kro to trusted-users
```

### Configuration Summary Matrix

| Node | CPU | Microarch | Cores | Threads | maxJobs | speedFactor | Tags |
|------|-----|-----------|-------|---------|---------|-------------|-------|
| **Zephyr** | Ryzen 9 5950X | znver3 | 16 | 32 | 8 | 8 | control-plane, k8s-master, k8s-node, local |
| **Nexus** | Ryzen 9 3900X | znver2 | 12 | 24 | 6 | 5 | storage, k8s-worker, k8s-storage, nvidia-gpu, remote |
| **Forge** | i5-9500 | skylake | 6 | 6 | 2 | 2 | gpu, compute, k8s-worker, k8s-gpu-mixed, remote |
| **Sentry** | Ryzen 7 1700 | znver1 | 8 | 16 | 4 | 4 | monitoring, k8s-worker, k8s-gpu-amd, remote |

### Key Capabilities After Implementation

✅ **CPU optimization**: Each node builds with `-march` tuned to its CPU
✅ **Selective deployment**: Deploy by tag (@storage, @gpu, @k8s-worker, etc.)
✅ **Distributed builds**: 42 cores total (8+6+2+4 maxJobs) across cluster
✅ **Parallel execution**: Colmena deploys to multiple nodes simultaneously via tags
✅ **Ad hoc evaluation**: Build/eval without activating
✅ **Local testing**: `apply-local` on Zephyr before remote deployment
✅ **Rolling updates**: Automated sequential deployment with K8s-safe order
✅ **Rollback safety**: Previous generations preserved for quick recovery
✅ **K8s-aware**: Tags and build priorities respect K8s control plane stability

### Performance Expectations

- **Better SIMD utilization**: AVX2 optimizations in compression, crypto, media (~10-30% improvement)
- **Faster package builds**: CPU-native compilation per node
- **Parallel deployment**: All remote nodes deploy simultaneously with tags
- **Build acceleration**: Distributed builds leverage all 42 cluster cores
- **K8s stability**: Conservative build allocations preserve control plane performance

---

## 9. Kubernetes Integration

### K8s-Aware Node Roles

As documented in [ROADMAP.md](../../ROADMAP.md), the cluster will migrate to Kubernetes over 9 weeks. This design is **Phase 0: Infrastructure Foundation** - establishing optimized NixOS infrastructure before K8s deployment.

**K8s role assignments:**

| Node | K8s Role (Phase 1+) | Build Strategy | Rationale |
|------|---------------------|----------------|-----------|
| **Zephyr** | K8s master + node | Conservative (8 maxJobs) | Control plane stability > build speed |
| **Nexus** | K8s storage worker | Moderate (6 maxJobs) | Headroom for NFS/PVC I/O |
| **Forge** | K8s GPU worker | Minimal (2 maxJobs) | GPU workloads need CPU, mixed vendor complexity |
| **Sentry** | K8s monitoring worker | Light (4 maxJobs) | Prometheus/Grafana/Loki need resources |

### K8s Deployment Patterns

```bash
# Deploy to K8s control plane only (zephyr)
just deploy-tag k8s-master

# Deploy to all K8s workers (nexus, forge, sentry)
just deploy-tag k8s-worker

# Deploy to K8s storage workers only
just deploy-tag k8s-storage

# Deploy to GPU nodes (NVIDIA or mixed)
just deploy-tag nvidia-gpu,k8s-gpu-mixed

# CRITICAL: Update K8s control plane FIRST, then workers
just deploy-v3-rolling  # Handles order automatically
```

### K8s Health Checks Integration

```bash
# After deploying to Zephyr (control plane)
ssh zephyr "kubectl get nodes"
ssh zephyr "kubectl get pods --all-namespaces"
ssh zephyr "systemctl status apiserver etcd kubelet"

# After deploying to workers
for host in nexus forge sentry; do
  echo "=== $host ==="
  ssh $host "kubectl get nodes | grep $host"
  ssh $host "systemctl status kubelet"
done

# For GPU workers specifically
ssh forge "kubectl describe node | grep -A10 'Allocated resources'"
ssh nexus "nvidia-smi"
```

### Why This Order Matters

**K8s best practices** (from official Kubernetes documentation):
- Upgrade control plane first, then workers
- Control plane must stay available during worker upgrades
- Upgrading control plane first ensures API compatibility

Our rolling update sequence follows this pattern:
**Zephyr (k8s-master) → Sentry (monitoring) → Nexus (storage) → Forge (GPU)**

---

## Success Criteria

### Quantitative Metrics

| Metric | Before | After | Target |
|--------|--------|-------|--------|
| Deployment time (all nodes) | ~15 min (manual) | ~5 min (parallel) | 67% reduction |
| Build parallelism | 16 cores (zephyr only) | 42 cores (cluster) | 163% increase |
| CPU optimization | Generic x86_64 | Per-node microarch | 10-30% faster |
| K8s control plane stability | Not applicable | Conservative builds | Zero downtime |

### Qualitative Metrics

- **Deployment flexibility**: Deploy by role, tag, or individual node
- **Rollback safety**: Previous generations preserved, quick recovery
- **K8s readiness**: Infrastructure optimized before container migration
- **Operational efficiency**: Faster builds, parallel deployments, automated rolling updates

---

## Risks and Mitigations

### Critical Risks

**Risk 1: Boot failure from CPU incompatibility**
- **Impact:** HIGH
- **Probability:** LOW
- **Mitigation:**
  - Build-only test phase before activation
  - Local deployment on Zephyr first (easiest rollback)
  - Dry-run validation for each remote node
  - Previous generations preserved

**Risk 2: Build interference with K8s workloads**
- **Impact:** MEDIUM
- **Probability:** LOW
- **Mitigation:**
  - Conservative maxJobs allocations (50% of cores)
  - K8s-aware build priorities (forge deprioritized)
  - MandatoryFeatures empty (don't force builds if K8s busy)

**Risk 3: Distributed build failures**
- **Impact:** MEDIUM
- **Probability:** LOW
- **Mitigation:**
  - Nix automatically falls back to local builds
  - Test SSH connectivity before enabling
  - Verify trusted-users configured on all nodes

### Medium Risks

**Risk 4: Increased disk usage from unique closures**
- **Impact:** LOW
- **Probability:** HIGH (certain to happen)
- **Mitigation:**
  - Acceptable trade-off for maximum optimization
  - Can use `nix.store.gc` to manage disk space
  - Consider binary cache for common packages in future

**Risk 5: K8s downtime during rolling updates**
- **Impact:** MEDIUM
- **Probability:** LOW
- **Mitigation:**
  - Update control plane first (maintains API availability)
  - Workers updated one-by-one
  - Each step validated before proceeding

---

## Next Steps

### Immediate (This Week)

1. ✅ Design approved (this document)
2. Create implementation plan (using writing-plans skill)
3. Begin Phase 1: Preparation
4. Execute Phase 2-6 sequentially

### This Month

1. Complete Colmena + v3 implementation
2. Validate all deployment patterns
3. Document workflows in CLAUDE.md
4. Begin K8s Phase 1 (ROADMAP.md)

### Ongoing

1. Monitor build performance and K8s stability
2. Adjust maxJobs if needed based on load
3. Add more tags as K8s workload evolves
4. Consider binary cache for shared packages

---

## References

**Internal Documentation:**
- [ROADMAP.md](../../ROADMAP.md) - Kubernetes migration plan
- [CLAUDE.md](../../CLAUDE.md) - Agent workflows and patterns
- [AGENTS.md](../../AGENTS.md) - MCP integration details
- [justfile](../../justfile) - Current deployment commands

**External Resources:**
- Colmena: https://colmena.cli.rs/
- NixOS distributed builds: https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html
- Kubernetes upgrades: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/
- NixOS K8s module: https://search.nixos.org/options?query=kubernetes

**Context7 Research:**
- Colmena tagging and deployment patterns
- NixOS K8s module configuration
- Kubernetes rolling upgrade best practices

---

**Last Updated:** 2026-03-09
**Status:** Design Approved → Ready for Implementation Plan
**Next Phase:** Create detailed implementation plan using writing-plans skill
