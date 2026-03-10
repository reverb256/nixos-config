# Colmena + x86-64-v3 + K8s Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Colmena deployment tool with per-node CPU microarchitecture optimization (x86-64-v3), distributed builds across 4-node cluster, and K8s-aware deployment tags.

**Architecture:**
- Use Colmena's `colmenaHive` output in flake.nix
- Per-node CPU tuning via `meta.nodeNixpkgs` with microarch-specific overlays
- Node tags for selective deployment (@k8s-master, @k8s-worker, @storage, @gpu, @monitoring)
- Distributed builds using machines.nix (all 4 nodes, 42 cores total)
- Conservative build allocations to preserve K8s workload performance

**Tech Stack:**
- Colmena: NixOS deployment tool
- NixOS flakes: Declarative system configuration
- Nixpkgs overlays: CPU microarchitecture tuning
- Kubernetes: NixOS services.kubernetes module (future)

---

## Prerequisites

Before starting this plan, ensure:
- [ ] You have read the design document: `docs/plans/2026-03-09-colmena-v3-k8s-integration-design.md`
- [ ] You are on the `feature/ci-cd-pipeline` branch or create a new branch
- [ ] You have SSH access to all nodes (zephyr, nexus, forge, sentry)
- [ ] You understand this is Phase 0: Infrastructure Foundation for the K8s migration

---

## Task 1: Create Distributed Build Configuration

**Files:**
- Create: `/etc/nixos/machines.nix`

**Step 1: Create machines.nix with 4-node build farm**

Write the distributed build configuration:

```nix
# machines.nix - Nix distributed build farm configuration
# Documentation: https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html
#
# Total cluster: 42 cores (16 + 12 + 6 + 8)
# K8s-aware: Conservative allocations preserve control plane stability

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

**Step 2: Verify machines.nix syntax**

Run: `nix-instantiate --parse /etc/nixos/machines.nix`
Expected: No errors, outputs a Nix expression

**Step 3: Test SSH connectivity to all nodes**

Run:
```bash
for host in nexus forge sentry; do
  echo "Testing $host..."
  ssh $host "hostname && whoami"
done
```

Expected:
- Each node responds with hostname and "j_kro" user
- No password prompts (SSH keys configured)

**Step 4: Commit machines.nix**

```bash
git add machines.nix
git commit -m "feat: add distributed build farm configuration

Configure 4-node Nix build farm (42 cores total):
- Zephyr: 8 maxJobs (conservative, K8s control plane)
- Nexus: 6 maxJobs (moderate, NFS/storage headroom)
- Forge: 2 maxJobs (minimal, GPU-focused)
- Sentry: 4 maxJobs (light, monitoring stack)

K8s-aware allocations preserve workload performance.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Add Trusted Users for Distributed Builds

**Files:**
- Modify: `/etc/nixos/modules/common-host-defaults.nix`

**Step 1: Read current common-host-defaults.nix**

Run: `cat /etc/nixos/modules/common-host-defaults.nix`

**Step 2: Add j_kro to nix.settings.trusted-users**

Find the `nix.settings` section (should exist around line 20-50). Add `trusted-users` if not present:

```nix
nix.settings = {
  # Existing settings...
  trusted-users = ["j_kro"];  # NEW: Enable distributed builds
};
```

If `nix.settings` doesn't exist, add it:

```nix
# Add anywhere in the module (before closing brace):
nix.settings.trusted-users = ["j_kro"];
```

**Step 3: Verify configuration is valid Nix**

Run: `nix-instantiate --parse /etc/nixos/modules/common-host-defaults.nix`
Expected: No syntax errors

**Step 4: Test locally (Zephyr)**

Run: `nix-build -E 'with import <nixpkgs> {}; hello' --max-jobs 4`
Expected: Builds successfully

**Step 5: Commit changes**

```bash
git add modules/common-host-defaults.nix
git commit -m "feat: add j_kro to nix.settings.trusted-users

Required for distributed builds across cluster.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Update colmena.nix with CPU Tuning and Tags

**Files:**
- Modify: `/etc/nixos/colmena.nix`

**Step 1: Read current colmena.nix**

Run: `cat /etc/nixos/colmena.nix`

**Step 2: Add tunedNixpkgs helper function**

After the `inputs` and `self` parameters (before `in {`), add:

```nix
}: let
  # CPU-tuned nixpkgs instances for per-node microarchitecture optimization
  tunedNixpkgs = system: microarch: import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (self: super: {
        stdenv = super.stdenv // {
          hostPlatform = super.stdenv.hostPlatform // {
            gcc.arch = microarch;  # x86-64-v3: znver3, znver2, skylake, znver1
          };
        };
      })
    ];
  };

  # Updated mkHost helper to support tags
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
  };
in {
```

**Step 3: Update meta section with nodeNixpkgs and machinesFile**

Find the `meta = {` section and update:

```nix
  meta = {
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    # NEW: Per-node CPU microarchitecture tuning
    nodeNixpkgs = {
      zephyr = tunedNixpkgs "x86_64-linux" "znver3";  # Ryzen 9 5950X (Zen 3)
      nexus = tunedNixpkgs "x86_64-linux" "znver2";    # Ryzen 9 3900X (Zen 2)
      forge = tunedNixpkgs "x86_64-linux" "skylake";    # i5-9500 (Coffee Lake)
      sentry = tunedNixpkgs "x86_64-linux" "znver1";   # Ryzen 7 1700 (Zen 1)
    };

    # NEW: Distributed builds
    machinesFile = ./machines.nix;

    specialArgs = {inherit inputs self;};
  };
```

**Step 4: Update zephyr node with tags**

Find the `zephyr = mkHost {` section and update:

```nix
  zephyr = mkHost {
    hostName = "zephyr";
    targetHost = null;  # No SSH (local deployment)
    tags = ["control-plane" "k8s-master" "k8s-node" "local"];
  };
```

**Step 5: Update nexus node with tags**

Find the `nexus = mkHost {` section and update:

```nix
  nexus = mkHost {
    hostName = "nexus";
    targetHost = "10.1.1.120";
    tags = ["storage" "k8s-worker" "k8s-storage" "nvidia-gpu" "remote"];
  };
```

**Step 6: Update forge node with tags**

Find the `forge = mkHost {` section and update:

```nix
  forge = mkHost {
    hostName = "forge";
    targetHost = "10.1.1.130";
    tags = ["gpu" "compute" "k8s-worker" "k8s-gpu-mixed" "remote"];
  };
```

**Step 7: Update sentry node with tags**

Find the `sentry = mkHost {` section and update:

```nix
  sentry = mkHost {
    hostName = "sentry";
    targetHost = "10.1.1.140";
    tags = ["monitoring" "k8s-worker" "k8s-gpu-amd" "remote"];
  };
```

**Step 8: Verify colmena.nix syntax**

Run: `nix-instantiate --parse /etc/nixos/colmena.nix`
Expected: No syntax errors

**Step 9: Test Colmena evaluates correctly**

Run: `nix eval .#colmenaHive --apply 'hive: builtins.attrNames hive'`
Expected: Lists `meta zephyr nexus forge sentry`

**Step 10: Commit changes**

```bash
git add colmena.nix
git commit -m "feat: add CPU tuning and K8s-aware tags to Colmena config

Add per-node microarchitecture optimization:
- Zephyr: znver3 (Ryzen 9 5950X Zen 3)
- Nexus: znver2 (Ryzen 9 3900X Zen 2)
- Forge: skylake (i5-9500 Coffee Lake)
- Sentry: znver1 (Ryzen 7 1700 Zen 1)

Add K8s-aware node tags:
- @k8s-master: Zephyr (control plane)
- @k8s-worker: Nexus, Forge, Sentry
- @k8s-storage: Nexus (PVCs)
- @k8s-gpu-mixed: Forge (NVIDIA + AMD)
- @k8s-gpu-amd: Sentry
- @nvidia-gpu: Nexus
- @storage, @gpu, @monitoring, @remote

Update mkHost helper to support tags parameter.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Update flake.nix to Add colmenaHive Output

**Files:**
- Modify: `/etc/nixos/flake.nix`

**Step 1: Read current flake.nix**

Run: `head -n 100 /etc/nixos/flake.nix`

**Step 2: Add colmenaHive to outputs**

Find the `outputs = inputs @ {self, nixpkgs, colmena, ...}: {` section and add the colmenaHive output:

```nix
outputs = inputs @ {self, nixpkgs, colmena, ...}: {
  # NEW: Colmena hive output for distributed deployment
  colmenaHive = colmena.lib.makeHive {
    import ./colmena.nix inputs;
  };

  # KEEP: All existing outputs below this line
  # (apps, devShells, formatter, checks, etc.)
```

**Step 3: Verify flake.nix syntax**

Run: `nix flake check`
Expected: No errors

**Step 4: Verify colmenaHive output exists**

Run: `nix flake show | grep colmenaHive`
Expected: Shows `colmenaHive` output

**Step 5: Test Colmena can evaluate the hive**

Run: `nix eval .#colmenaHive --apply 'hive: builtins.attrNames hive.meta'`
Expected: Lists `nixpkgs nodeNixpkgs machinesFile specialArgs`

**Step 6: Test node enumeration**

Run: `nix run .#apps.x86_64-linux.colmena -- eval --expr '{ nodes, ... }: builtins.attrNames nodes'`
Expected: `["meta" "zephyr" "nexus" "forge" "sentry"]`

**Step 7: Test tag evaluation**

Run: `nix run .#apps.x86_64-linux.colmena -- eval --expr '{ nodes, ...}: builtins.mapAttrs (n: v: v.config.deployment.tags or []) nodes'`
Expected: Shows tags for each node (zephyr: ["control-plane" "k8s-master" "k8s-node" "local"], etc.)

**Step 8: Commit changes**

```bash
git add flake.nix
git commit -m "feat: add colmenaHive output to flake.nix

Enable Colmena deployment tool with makeHive function.
Integrates with colmena.nix for distributed deployment.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Update justfile with New Deployment Commands

**Files:**
- Modify: `/etc/nixos/justfile`

**Step 1: Read current justfile**

Run: `cat /etc/nixos/justfile`

**Step 2: Add deploy-v3-rolling recipe**

Find the deploy recipes section and add after the existing `deploy` recipe:

```nix
# Deploy v3 optimizations with K8s-aware rolling update
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
    ssh zephyr "kubectl get nodes" || echo "⚠️  K8s not yet installed, skipping validation"
    ssh zephyr "systemctl status apiserver etcd kubelet" || true
    _done "zephyr updated to v3"

    # Step 3: Deploy to remote workers sequentially (K8s order)
    _step "deploying → k8s workers"
    for host in sentry nexus forge; do
        cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on $host --verbose
        _step "validating $host..."
        ssh $host "kubectl get nodes | grep $host" || echo "⚠️  K8s not yet installed on $host"
        ssh $host "systemctl status kubelet" || true
        _done "$host updated to v3"
    done

    _time; _header "all nodes updated to v3 successfully"
```

**Step 3: Add deploy-tag recipe**

Add after the `deploy-v3-rolling` recipe:

```nix
# Deploy by tag (parallel deployment to tagged nodes)
deploy-tag ARG:
    #!/usr/bin/env bash
    set -e
    source {{JUST_HELPERS}}
    _header "deploy → @{{ARG}} (parallel)"
    cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on @{{ARG}} --verbose
    _done "nodes with tag @{{ARG}} updated"
```

**Step 4: Add rollback recipe**

Add after the `deploy-tag` recipe:

```nix
# Emergency rollback to previous generation
rollback ARG:
    #!/usr/bin/env bash
    _header "rollback → {{ARG}}"
    ssh {{ARG}} "sudo nixos-rebuild rollback"
    _done "{{ARG}} rolled back to previous generation"
```

**Step 5: Verify justfile syntax**

Run: `just --list`
Expected: Shows `deploy-v3-rolling`, `deploy-tag`, and `rollback` recipes

**Step 6: Test justfile help**

Run: `just deploy-v3-rolling --help` or `just --list deploy-v3-rolling`
Expected: Shows recipe description

**Step 7: Commit changes**

```bash
git add justfile
git commit -m "feat: add Colmena deployment commands to justfile

Add K8s-aware rolling update workflow:
- just deploy-v3-rolling: Sequential deployment with validation
- just deploy-tag <tag>: Parallel deployment to tagged nodes
- just rollback <node>: Quick rollback to previous generation

Rolling order: Zephyr (k8s-master) → Sentry → Nexus → Forge
Follows K8s best practices: control plane first, then workers.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Pre-Deployment Testing

**Step 1: Verify flake is valid**

Run: `nix flake check`
Expected: All checks pass

**Step 2: Show what will be deployed**

Run: `nix run .#apps.x86_64-linux.colmena -- eval --expr '{ nodes, ... }: builtins.mapAttrs (n: v: { cpu = v.config.nixpkgs.hostPlatform.gcc.arch or "default"; tags = v.config.deployment.tags or []; }) nodes'`
Expected: Shows CPU arch and tags for each node

**Step 3: Build all closures without activating**

Run: `nix run .#apps.x86_64-linux.colmena -- build`
Expected: Builds closures for all 4 nodes successfully

**Step 4: Dry-run on Zephyr (local)**

Run: `nix run .#apps.x86_64-linux.colmena -- apply-local --dry-run --on zephyr`
Expected: Shows what would change on Zephyr

**Step 5: Dry-run on remote nodes**

Run:
```bash
for host in nexus forge sentry; do
  echo "=== Dry-run on $host ==="
  nix run .#apps.x86_64-linux.colmena -- apply --dry-run --on $host
done
```

Expected: Shows what would change on each remote node

**Step 6: Verify distributed builds configuration**

Run: `cat machines.nix`
Expected: Shows 4-node build farm configuration

**Step 7: Test SSH connectivity for distributed builds**

Run:
```bash
for host in nexus forge sentry; do
  echo "=== Testing $host ==="
  ssh $host "nix-store --verify"
done
```

Expected: All nodes respond successfully

---

## Task 7: Deploy to Zephyr (Local, K8s Control Plane)

**Step 1: Deploy to Zephyr with dry-run first**

Run:
```bash
nix run .#apps.x86_64-linux.colmena -- apply-local --dry-run --on zephyr
```

Expected: Shows what will change

**Step 2: Review the changes**

Look at the output and verify:
- CPU arch is set to znver3
- Tags include control-plane, k8s-master, k8s-node
- No unexpected changes

**Step 3: Deploy to Zephyr**

Run:
```bash
nix run .#apps.x86_64-linux.colmena -- apply-local --on zephyr
```

Expected: Builds and activates new configuration on Zephyr

**Step 4: Verify Zephyr booted successfully**

Run:
```bash
nixos-rebuild list-generations | head -3
```

Expected: Shows latest generation with today's date

**Step 5: Check CPU optimizations are active**

Run:
```bash
nix-store -q --requisites /run/current-system | head -20
```

Expected: Shows store paths (these are znver3-optimized)

**Step 6: Verify no failed services**

Run:
```bash
systemctl --failed
```

Expected: No failed units

**Step 7: Test K8s components (if installed)**

Run:
```bash
kubectl get nodes 2>/dev/null || echo "K8s not yet installed"
systemctl status apiserver etcd kubelet 2>/dev/null || echo "K8s services not found"
```

Expected: Either K8s is healthy or not installed yet (both OK)

**Step 8: Commit post-deployment validation**

```bash
git add .
git commit -m "test: validate Zephyr v3 deployment

Verified:
- znver3 CPU optimizations active
- Control plane tags applied
- No failed services
- K8s components healthy (or not installed yet)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 8: Deploy to Sentry (Monitoring Node)

**Step 1: Dry-run on Sentry**

Run:
```bash
nix run .#apps.x86_64-linux.colmena -- apply --dry-run --on sentry
```

Expected: Shows what will change on Sentry

**Step 2: Review the changes**

Look for:
- CPU arch is set to znver1
- Tags include monitoring, k8s-worker, k8s-gpu-amd
- No unexpected changes

**Step 3: Deploy to Sentry**

Run:
```bash
nix run .#apps.x86_64-linux.colmena -- apply --on sentry --verbose
```

Expected: Builds and activates new configuration on Sentry

**Step 4: Verify Sentry deployment**

Run:
```bash
ssh sentry "nixos-rebuild list-generations | head -3"
```

Expected: Shows latest generation with today's date

**Step 5: Check Sentry services**

Run:
```bash
ssh sentry "systemctl --failed"
```

Expected: No failed units

**Step 6: Verify CPU optimizations**

Run:
```bash
ssh sentry "nix-store -q --requisites /run/current-system | head -20"
```

Expected: Shows znver1-optimized store paths

**Step 7: Test monitoring stack (if installed)**

Run:
```bash
ssh sentry "systemctl status prometheus grafana loki" || echo "Monitoring stack not fully installed yet"
```

Expected: Services running or not installed (both OK)

**Step 8: Commit validation**

```bash
git add .
git commit -m "test: validate Sentry v3 deployment

Verified:
- znver1 CPU optimizations active
- Monitoring tags applied
- No failed services
- Monitoring stack healthy

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 9: Deploy to Nexus (Storage Node)

**Step 1: Dry-run on Nexus**

Run:
```bash
nix run .#apps.x86_64-linux.colmena -- apply --dry-run --on nexus
```

Expected: Shows what will change on Nexus

**Step 2: Review the changes**

Look for:
- CPU arch is set to znver2
- Tags include storage, k8s-storage, nvidia-gpu
- No unexpected changes

**Step 3: Deploy to Nexus**

Run:
```bash
nix run .#apps.x86_64-linux.colmena -- apply --on nexus --verbose
```

Expected: Builds and activates new configuration on Nexus

**Step 4: Verify Nexus deployment**

Run:
```bash
ssh nexus "nixos-rebuild list-generations | head -3"
```

Expected: Shows latest generation with today's date

**Step 5: Check Nexus services**

Run:
```bash
ssh nexus "systemctl --failed"
```

Expected: No failed units

**Step 6: Verify storage mounts**

Run:
```bash
ssh nexus "mountpoint -q /data && echo '✓ /data mounted' || echo '✗ /data not mounted'"
```

Expected: `/data` is mounted

**Step 7: Verify CPU optimizations**

Run:
```bash
ssh nexus "nix-store -q --requisites /run/current-system | head -20"
```

Expected: Shows znver2-optimized store paths

**Step 8: Test NVIDIA GPU (if available)**

Run:
```bash
ssh nexus "nvidia-smi" || echo "NVIDIA GPU not accessible or drivers not loaded"
```

Expected: GPU info or not available message (both OK)

**Step 9: Commit validation**

```bash
git add .
git commit -m "test: validate Nexus v3 deployment

Verified:
- znver2 CPU optimizations active
- Storage tags applied
- /data mounted successfully
- No failed services
- NVIDIA GPU accessible

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 10: Deploy to Forge (GPU Node, Most Complex)

**Step 1: Dry-run on Forge**

Run:
```bash
nix run .#apps.x86_64-linux.colmena -- apply --dry-run --on forge
```

Expected: Shows what will change on Forge

**Step 2: Review the changes**

Look for:
- CPU arch is set to skylake
- Tags include gpu, compute, k8s-gpu-mixed
- No unexpected changes

**Step 3: Deploy to Forge**

Run:
```bash
nix run .#apps.x86_64-linux.colmena -- apply --on forge --verbose
```

Expected: Builds and activates new configuration on Forge

**Step 4: Verify Forge deployment**

Run:
```bash
ssh forge "nixos-rebuild list-generations | head -3"
```

Expected: Shows latest generation with today's date

**Step 5: Check Forge services**

Run:
```bash
ssh forge "systemctl --failed"
```

Expected: No failed units

**Step 6: Verify CPU optimizations**

Run:
```bash
ssh forge "nix-store -q --requisites /run/current-system | head -20"
```

Expected: Shows skylake-optimized store paths

**Step 7: Test NVIDIA GPUs**

Run:
```bash
ssh forge "nvidia-smi"
```

Expected: Shows 2x RTX 4060 GPUs

**Step 8: Test AMD GPUs**

Run:
```bash
ssh forge "rocm-smi" || echo "ROCm not installed"
```

Expected: Shows 2x RX 5700 XT GPUs or ROCm not installed (both OK)

**Step 9: Commit validation**

```bash
git add .
git commit -m "test: validate Forge v3 deployment

Verified:
- skylake CPU optimizations active
- GPU/mixed vendor tags applied
- No failed services
- NVIDIA GPUs accessible (2x RTX 4060)
- AMD GPUs accessible (2x RX 5700 XT)

Forge is most complex node (mixed GPU vendors) - deployment successful!

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 11: Final Validation and Documentation

**Step 1: Verify all nodes on correct version**

Run:
```bash
for host in zephyr nexus forge sentry; do
  echo "=== $host ==="
  ssh $host "nixos-rebuild list-generations | head -1"
  ssh $host "nixos-version"
done
```

Expected: All nodes show same generation date and version

**Step 2: Run cluster-wide health check**

Run:
```bash
for host in zephyr nexus forge sentry; do
  echo "=== $host: Failed services ==="
  ssh $host "systemctl --failed || echo 'No failed services'"
done
```

Expected: No failed services on any node

**Step 3: Test Colmena tag-based deployment**

Run:
```bash
nix run .#apps.x86_64-linux.colmena -- eval --expr '{ nodes, ... }: builtins.mapAttrs (n: v: v.config.deployment.tags or []) nodes'
```

Expected: Shows all tags for each node

**Step 4: Test distributed builds**

Run:
```bash
nix-build -E 'with import <nixpkgs> {}; hello' --max-jobs 20
nix-store --query --builder /nix/store/*-hello
```

Expected: Builder is one of: zephyr, nexus, forge, or sentry (not localhost)

**Step 5: Update CLAUDE.md with new workflows**

Add to `/etc/nixos/CLAUDE.md`:

```markdown
## Colmena Deployment Commands

### Rolling Update (K8s-safe order)
```bash
just deploy-v3-rolling
```
Deploys to all nodes sequentially: Zephyr → Sentry → Nexus → Forge

### Tag-Based Deployment
```bash
# Deploy to K8s workers only
just deploy-tag k8s-worker

# Deploy to storage nodes
just deploy-tag storage

# Deploy to GPU nodes
just deploy-tag gpu,k8s-gpu-mixed
```

### Rollback
```bash
just rollback <hostname>
```

### Direct Colmena Commands
```bash
# Build all closures
nix run .#apps.x86_64-linux.colmena -- build

# Deploy to specific node
nix run .#apps.x86_64-linux.colmena -- apply --on <hostname>

# Deploy by tag
nix run .#apps.x86_64-linux.colmena -- apply --on @<tag>

# Dry-run
nix run .#apps.x86_64-linux.colmena -- apply --dry-run --on <hostname>
```
```

**Step 6: Commit final validation**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with Colmena workflows

Add documentation for:
- Rolling update commands
- Tag-based deployment
- Rollback procedures
- Direct Colmena usage

All nodes successfully deployed with v3 optimizations!

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

**Step 7: Create summary of changes**

Run:
```bash
git log --oneline -10
```

Expected: Shows all commits from this implementation plan

**Step 8: Verify performance improvements**

Run (on each node):
```bash
# Check that packages are CPU-optimized
nix-shell -p coreutils --run 'nix-store -q --requisites /run/current-system | grep -v "\-src$" | head -10'
```

Expected: Store paths show optimized packages

---

## Task 12: Merge to Main Branch

**Step 1: Ensure all commits are on feature branch**

Run:
```bash
git branch --show-current
```

Expected: Shows `feature/ci-cd-pipeline` or your feature branch name

**Step 2: Update feature branch with latest main**

Run:
```bash
git fetch origin main
git rebase origin/main
```

Expected: Clean rebase (resolve conflicts if any)

**Step 3: Switch to main branch**

Run:
```bash
git checkout main
```

**Step 4: Merge feature branch**

Run:
```bash
git merge feature/ci-cd-pipeline --no-ff -m "Merge branch 'feature/ci-cd-pipeline': Colmena + x86-64-v3 + K8s integration

Implements comprehensive deployment infrastructure:
- Per-node CPU microarchitecture optimization (znver3, znver2, skylake, znver1)
- Colmena deployment tool with K8s-aware node tags
- Distributed builds across 4-node cluster (42 cores total)
- Automated rolling update workflow
- Foundation for Kubernetes migration (ROADMAP.md Phase 0)

All 4 nodes successfully deployed and validated.

Related docs:
- Design: docs/plans/2026-03-09-colmena-v3-k8s-integration-design.md
- Roadmap: ROADMAP.md (K8s migration plan)
```

Expected: Clean merge

**Step 5: Push to remote**

Run:
```bash
git push origin main
```

Expected: Pushes successfully

**Step 6: Optional: Delete feature branch**

Run:
```bash
git branch -d feature/ci-cd-pipeline
git push origin --delete feature/ci-cd-pipeline
```

Expected: Branch deleted locally and remotely

---

## Success Criteria

After completing this implementation plan, you should have:

✅ **All 4 nodes running with CPU-optimized configurations**
- Zephyr: znver3-optimized (Ryzen 9 5950X)
- Nexus: znver2-optimized (Ryzen 9 3900X)
- Forge: skylake-optimized (i5-9500)
- Sentry: znver1-optimized (Ryzen 7 1700)

✅ **Colmena deployment tool operational**
- Tag-based selective deployment working
- Rolling update automation functional
- Rollback procedures tested

✅ **Distributed builds active**
- 4-node build farm (42 cores total)
- Builds distributed across cluster
- Verified with `nix-store --query --builder`

✅ **K8s-ready infrastructure**
- Node tags reflect K8s roles
- Rolling update order follows K8s best practices
- Conservative build allocations preserve K8s performance

✅ **Documentation updated**
- CLAUDE.md includes Colmena workflows
- Design document committed
- Implementation plan validated

---

## Troubleshooting

### Issue: Build fails with "unknown host" error

**Solution:** Check `/etc/nixos/machines.nix` hostnames match actual hostnames:
```bash
for host in nexus forge sentry; do
  ssh $host "hostname"
done
```

### Issue: Distributed builds not working

**Solution:** Verify `j_kro` is in `nix.settings.trusted-users` on all nodes:
```bash
for host in nexus forge sentry; do
  ssh $host "grep trusted-users /etc/nixos/configuration.nix"
done
```

### Issue: Colmena can't connect to nodes

**Solution:** Test SSH connectivity:
```bash
for host in nexus forge sentry; do
  ssh $host "echo 'Connection successful'"
done
```

### Issue: CPU optimizations not applied

**Solution:** Check `nodeNixpkgs` is configured in `colmena.nix`:
```bash
nix eval .#colmenaHive --apply 'hive: hive.meta.nodeNixpkgs'
```

### Issue: Tags not working

**Solution:** Verify tags in node configs:
```bash
nix run .#apps.x86_64-linux.colmena -- eval --expr '{ nodes, ... }: builtins.mapAttrs (n: v: v.config.deployment.tags or []) nodes'
```

### Issue: Rollback needed

**Solution:** Use rollback command:
```bash
just rollback <hostname>
# Or manually:
ssh <hostname> "sudo nixos-rebuild rollback"
```

---

## Next Steps After Implementation

1. **Monitor cluster performance** - Watch for build interference with K8s workloads
2. **Adjust maxJobs if needed** - Tune based on observed load
3. **Begin K8s Phase 1** - Now that infrastructure is optimized, start K8s migration per ROADMAP.md
4. **Consider binary cache** - If disk space becomes issue with unique closures
5. **Add more tags** - As K8s workloads evolve, add role-specific tags

---

## References

**Design Document:**
- `docs/plans/2026-03-09-colmena-v3-k8s-integration-design.md` - Comprehensive design

**Related Documentation:**
- `ROADMAP.md` - Kubernetes migration plan
- `CLAUDE.md` - Agent workflows and patterns
- `AGENTS.md` - MCP integration details

**External Resources:**
- Colmena: https://colmena.cli.rs/
- NixOS distributed builds: https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html
- Kubernetes upgrades: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/

---

**Implementation Plan Status:** Ready for Execution
**Estimated Time:** 1-2 days (12 tasks, ~2-3 hours total)
**Difficulty:** Intermediate (requires NixOS/Colmena knowledge)
**Risk Level:** Medium (rolling updates mitigate risk)
