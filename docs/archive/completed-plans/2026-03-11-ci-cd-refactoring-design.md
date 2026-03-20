# CI/CD Refactoring Design: Colmena + GitHub Actions Standardization

**Date:** 2026-03-11
**Status:** Draft
**Author:** Claude Code Agent (with user feedback)

## Executive Summary

This design document outlines a comprehensive refactoring of the NixOS cluster's CI/CD infrastructure to:
1. **Standardize all deployments on Colmena** (single source of truth)
2. **Fix inconsistencies** between justfile, GitHub Actions, and manual workflows
3. **Add visibility** into deployment status across all 4 nodes
4. **Integrate GPU scheduling** to prevent deployment conflicts with AI workloads

**Key Decision:** Create a `nixos-rebuild` wrapper that translates commands to Colmena, providing backward compatibility while enforcing consistent deployment behavior.

---

## Problem Statement

### Current Issues Identified (from CI/CD Audit)

**Inconsistency (Category A):**
- `just deploy` uses Colmena properly ✅
- `.github/workflows/deploy.yml` uses raw SSH ❌
- Different mining service names (`lolminer-nvidia` vs `lolminer-*` vs `xmrig@*`)
- CI builds for unused architectures (`--all-systems` flag)

**Visibility (Category C):**
- No single view of deployment status across cluster
- Can't easily tell which host is building/deploying
- No centralized build logs or failure summaries
- Hard to debug deployment failures

**GPU Scheduling Integration:**
- Deployments don't coordinate with AI workloads
- Mining may not pause correctly during deployments
- No signaling to `/run/gpu-scheduler/ai-state`

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Standardized Deployment Flow                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  All Deployment Triggers                                            │
│  ├─ just deploy                                                     │
│  ├─ GitHub Actions (push/manual)                                    │
│  ├─ Manual: nixos-rebuild switch                                    │
│  └─ Scripts calling nixos-rebuild                                   │
│         │                                                           │
│         ▼                                                           │
│  ┌───────────────────────────────────────────────┐                  │
│  │  nixos-rebuild-wrapper (NEW)                 │                  │
│  │  ├─ Translates to Colmena commands           │                  │
│  │  ├─ Signals GPU scheduler                    │                  │
│  │  ├─ Pauses/resumes mining                    │                  │
│  │  ├─ Writes state files                       │                  │
│  │  └─ Shows visual progress                    │                  │
│  └───────────────────────────────────────────────┘                  │
│         │                                                           │
│         ▼                                                           │
│  ┌───────────────────────────────────────────────┐                  │
│  │  Colmena (Single Source of Truth)            │                  │
│  │  ├─ Builds all configurations               │                  │
│  │  ├─ Manages dependencies                    │                  │
│  │  └─ Applies to cluster nodes                 │                  │
│  └───────────────────────────────────────────────┘                  │
│         │                                                           │
│         ▼                                                           │
│  Cluster Nodes (Zephyr, Nexus, Forge, Sentry)                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component Design

### 1. Nixos-Rebuild Wrapper

**Location:** `/etc/nixos/scripts/nixos-rebuild-wrapper`

**Command Translations:**

| Command | Translation |
|---------|-------------|
| `nixos-rebuild switch` | `colmena apply --on $(hostname) --verbose` |
| `nixos-rebuild build` | `colmena build --on $(hostname)` |
| `nixos-rebuild test` | `colmena apply --on $(hostname) --eval-only` |
| `nixos-rebuild dry-activate` | `colmena apply --on $(hostname) --dry-activate` |
| `nixos-rebuild rollback` | Bypass wrapper, use native nixos-rebuild |

**Key Features:**

1. **GPU-Aware Deployment**
   ```bash
   # Detect NVIDIA GPU nodes
   if [[ "$HOST" =~ ^(zephyr|nexus|forge)$ ]]; then
     echo "DEPLOY_IN_PROGRESS" > /run/gpu-scheduler/ai-state
   fi
   # Sentry (AMD GPU) skips signaling
   ```

2. **Mining Pause/Resume**
   ```bash
   # Before deploy
   systemctl stop mining.target

   # After deploy
   systemctl start mining.target
   ```

3. **State File Writing**
   ```bash
   # /run/nixos-deploy/{host}.json
   {
     "host": "zephyr",
     "status": "deploying",
     "started_at": "2026-03-11T21:30:00Z",
     "deployed_by": "github-actions",
     "git_commit": "ec62937",
     "git_branch": "feature/ci-cd-pipeline",
     "gpu_nodes_paused": true
   }
   ```

4. **Visual Progress Output**
   ```bash
   echo "🔨 building zephyr..."
   echo "🚀 deploying zephyr..."
   echo "✓ zephyr deployed successfully (generation 387)"
   ```

5. **Bypass Mechanism**
   - Use `NIXOS_REBUILD_NATIVE=1` env var
   - Or call `/run/current-system/sw/bin/nixos-rebuild` directly

**NixOS Module:** `modules/system/nixos-rebuild-wrapper.nix`

```nix
{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "nixos-rebuild" ''
      # Wrapper script content
    '')
  ];

  # Create state directory
  systemd.tmpfiles.rules = [
    "d /run/nixos-deploy 0755 root root"
  ];
}
```

---

### 2. GitHub Actions Workflows

#### Fix 1: Remove Silent Linter Failures

**File:** `.github/workflows/ci.yml`

```yaml
# BEFORE (lines 52-58)
- name: Run statix
  run: nix shell nixpkgs#statix --command statix check .
  continue-on-error: true  # ❌

# AFTER
- name: Run statix
  run: nix shell nixpkgs#statix --command statix check .
  # Remove continue-on-error - fail on issues
```

#### Fix 2: Remove Wasteful Multi-Arch Builds

**File:** `.github/workflows/ci.yml`

```yaml
# BEFORE (line 34)
run: nix flake check --all-systems  # Builds aarch64 unnecessarily

# AFTER
run: nix flake check  # Only x86_64-linux
```

#### Fix 3: Use Colmena for Deployment

**File:** `.github/workflows/deploy.yml`

```yaml
# BEFORE (line 62)
- name: Deploy to hosts
  run: |
    ssh $host "sudo nixos-rebuild switch --flake /etc/nixos#$host"

# AFTER
- name: Deploy to hosts
  run: |
    cd /etc/nixos
    nix run .#apps.x86_64-linux.colmena -- apply --on $host --verbose
```

#### Fix 4: Add GPU Scheduling

**File:** `.github/workflows/deploy.yml`

```yaml
- name: Deploy with GPU awareness
  run: |
    for host in zephyr nexus forge; do
      # Signal deployment starting
      ssh $host "echo 'DEPLOY_IN_PROGRESS' > /run/gpu-scheduler/ai-state"

      # Deploy via Colmena
      nix run .#apps.x86_64-linux.colmena -- apply --on $host

      # Signal deployment complete
      ssh $host "echo '' > /run/gpu-scheduler/ai-state"
    done
```

#### Fix 5: Unify Mining Service Names

**File:** `.github/workflows/deploy.yml`

```yaml
# BEFORE (lines 39-40, 102-103)
sudo systemctl stop xmrig@* || true
sudo systemctl stop lolminer-* || true

# AFTER (add systemd target first, then use it)
sudo systemctl stop mining.target
```

**Note:** Must add `mining.target` to `modules/mining/mining.nix`:
```nix
systemd.targets.mining = {
  description = "All mining services";
  wants = [ "lolminer-nvidia.service" "xmrig@amd.service" ];
};
```

---

### 3. justfile Standardization

#### Fix 1: Consistent Colmena Usage

**File:** `justfile`

```bash
# BEFORE (deploy-v3-rolling, line 101)
cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply-local --on zephyr

# AFTER (all deployments use apply --on)
cd {{FLAKE_PATH}} && nix run .#apps.x86_64-linux.colmena -- apply --on zephyr
```

#### Fix 2: Match CI Lint Behavior

**File:** `justfile`

```bash
# BEFORE (ci-local, lines 343-346)
statix check . || true
deadnix -f . || true

# AFTER (warn but don't fail, or fail to match CI)
statix check . || _warn "Statix issues found"
deadnix -f . || _warn "Deadnix issues found"
```

#### New Commands: Visibility

```bash
# Show deployment status across cluster
status-cluster:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _header "cluster → deployment status"
    for host in zephyr nexus forge sentry; do
      _step "$host..."
      if [ "$host" = "$(hostname -s)" ]; then
        cat /run/nixos-deploy/$host.json 2>/dev/null || echo "No recent deploy"
      else
        ssh $host "cat /run/nixos-deploy/$host.json" 2>/dev/null || echo "No recent deploy"
      fi
    done

# Watch deployments in real-time with visuals
watch-deploy:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}

    while true; do
      clear
      _header "Cluster Deployment Status (live)"
      echo ""

      for host in zephyr nexus forge sentry; do
        state="/run/nixos-deploy/$host.json"
        if [ -f "$state" ]; then
          status=$(jq -r '.status' $state 2>/dev/null || echo "unknown")
          started=$(jq -r '.started_at' $state 2>/dev/null || echo "unknown")

          case $status in
            building)
              printf "  \033[1;33m🔨\033[0m %-8s Building...\n" "$host"
              ;;
            deploying)
              printf "  \033[1;33m🚀\033[0m %-8s Deploying...\n" "$host"
              ;;
            success)
              gen=$(jq -r '.generation // "unknown"' $state)
              printf "  \033[1;32m✓\033[0m %-8s Deployed (gen $gen)\n" "$host"
              ;;
            failed)
              printf "  \033[1;31m✗\033[0m %-8s Failed\n" "$host"
              ;;
          esac
        else
          printf "  \033[2;90m○\033[0m %-8s Idle\n" "$host"
        fi
      done

      echo ""
      echo "Refreshing every 2s (Ctrl+C to exit)"
      sleep 2
    done

# Clean up old state files
clean-deploy-state:
    #!/usr/bin/env bash
    source {{JUST_HELPERS}}
    _step "cleaning state files older than 7 days..."
    find /run/nixos-deploy -name "*.json" -mtime +7 -delete 2>/dev/null || true
    _done "cleanup complete"
```

---

### 4. GPU Scheduling Integration

**Deploy → GPU Scheduler Signaling:**

```bash
# Wrapper adds this for NVIDIA GPU nodes (zephyr, nexus, forge)
deploy_to_nvidia_node() {
  local host=$1

  # Step 1: Signal deployment starting
  echo "DEPLOY_IN_PROGRESS" > /run/gpu-scheduler/ai-state

  # k8s-gpu-scheduler DaemonSet detects state, scales mining → 0

  # Step 2: Deploy via Colmena
  colmena apply --on $host

  # Step 3: Signal deployment complete
  echo "" > /run/gpu-scheduler/ai-state

  # k8s-gpu-scheduler DaemonSet scales mining → 1
}
```

**Integration with Existing Signals:**

| State | Written By | Action |
|-------|-----------|--------|
| `AI_START` | AI Inference Gateway | k8s-scheduler scales mining→0, bare metal stops lolminer |
| `AI_STOP` | AI Inference Gateway | k8s-scheduler scales mining→1, bare metal starts lolminer |
| `DEPLOY_IN_PROGRESS` | nixos-rebuild-wrapper | k8s-scheduler scales mining→0 |
| `` (empty) | nixos-rebuild-wrapper (after deploy) | k8s-scheduler scales mining→1 |

**Update Required to `scripts/k8s-gpu-scheduler.py`:**

```python
# Add DEPLOY_IN_PROGRESS to state handling
def handle_deploy_state(state: str) -> None:
    """Handle deployment in progress state"""
    if state == "DEPLOY_IN_PROGRESS":
        # Scale mining deployments to 0
        scale_deployment("gpu-miner-zephyr", 0)
        scale_deployment("gpu-miner-forge", 0)
        logger.info("Deploy in progress - mining paused")
    else:
        # Resume mining
        scale_deployment("gpu-miner-zephyr", 1)
        scale_deployment("gpu-miner-forge", 1)
        logger.info("Deploy complete - mining resumed")
```

---

### 5. Visibility & Monitoring

**State Files:** `/run/nixos-deploy/{host}.json`

```json
{
  "host": "zephyr",
  "status": "deploying",
  "started_at": "2026-03-11T21:30:00Z",
  "deployed_by": "github-actions",
  "git_commit": "ec62937",
  "git_branch": "feature/ci-cd-pipeline",
  "generation": "387",
  "deploy_time_seconds": 135,
  "gpu_nodes_paused": true
}
```

**Status Values:**
- `building` - Colmena building configuration
- `deploying` - Applying configuration to node
- `success` - Deployment completed successfully
- `failed` - Deployment failed (check logs)

**New GitHub Actions Workflow:** `.github/workflows/cluster-status.yml`

```yaml
name: Cluster Status

on:
  schedule:
    - cron: '*/5 * * * *'  # Every 5 minutes
  workflow_dispatch:

permissions:
  contents: read

jobs:
  status:
    name: Cluster Status
    runs-on: [self-hosted, nixos]
    steps:
      - name: Check cluster state
        run: |
          echo "## 🚀 Cluster Deployment Status" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Host | Status | Time | Generation |" >> $GITHUB_STEP_SUMMARY
          echo "|------|--------|------|------------|" >> $GITHUB_STEP_SUMMARY

          for host in zephyr nexus forge sentry; do
            state="/run/nixos-deploy/$host.json"
            if [ -f "$state" ]; then
              status=$(jq -r '.status' $state)
              started=$(jq -r '.started_at' $state)
              time_ago=$(($(date +%s) - $(date -d "$started" +%s)))
              gen=$(jq -r '.generation // "N/A"' $state)

              case $status in
                success) emoji="✅" ;;
                failed) emoji="❌" ;;
                deploying) emoji="🚀" ;;
                building) emoji="🔨" ;;
                *) emoji="⏳" ;;
              esac

              echo "| $host | $emoji $status | ${time_ago}s ago | $gen |" >> $GITHUB_STEP_SUMMARY
            else
              echo "| $host | ⚪ No recent deploy | - | - |" >> $GITHUB_STEP_SUMMARY
            fi
          done
```

---

### 6. Error Handling & Rollback

**Deployment Error Recovery:**

```bash
deploy_with_rollback() {
  local host=$1

  # Get current generation before deploy
  local current_gen=$(ssh $host "readlink /run/current-system" || echo "unknown")

  # Update state: building
  echo "{\"host\":\"$host\",\"status\":\"building\",\"started_at\":\"$(date -Iseconds)\",\"previous_generation\":\"$current_gen\"}" > /run/nixos-deploy/$host.json

  # Build
  if ! colmena build --on $host; then
    echo "{\"host\":\"$host\",\"status\":\"failed\",\"error\":\"build failed\"}" > /run/nixos-deploy/$host.json
    return 1
  fi

  # Update state: deploying
  echo "{\"host\":\"$host\",\"status\":\"deploying\"}" >> /run/nixos-deploy/$host.json

  # Deploy
  if ! colmena apply --on $host; then
    echo "❌ Deploy failed for $host, rolling back..."

    # Rollback to previous generation
    ssh $host "sudo nixos-rebuild rollback"

    # Update state with failure
    cat > /run/nixos-deploy/$host.json <<EOF
{
  "host": "$host",
  "status": "failed",
  "rolled_back": true,
  "previous_generation": "$current_gen",
  "error": "deployment failed, auto-rollback executed"
}
EOF

    return 1
  fi

  # Update state: success
  local new_gen=$(ssh $host "readlink /run/current-system")
  cat > /run/nixos-deploy/$host.json <<EOF
{
  "host": "$host",
  "status": "success",
  "completed_at": "$(date -Iseconds)",
  "generation": "$(basename $new_gen)"
}
EOF
}
```

**GitHub Actions Error Aggregation** (already in deploy.yml, keep this pattern):

```yaml
# Track failures
FAILED_HOSTS=()

for host in zephyr nexus forge sentry; do
  deploy_with_rollback $host || FAILED_HOSTS+=("$host")
done

# Exit with error if any deployments failed
if [ ${#FAILED_HOSTS[@]} -gt 0 ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "ERROR: Deployment failed for: ${FAILED_HOSTS[*]}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi
```

---

### 7. Testing Strategy

**Pre-deployment Validation (add to `scripts/pre-deploy-check.sh`):**

```bash
# Check 1: Verify wrapper is installed on all nodes
check_wrapper_installed() {
  section "Wrapper Installation Check"

  for host in zephyr nexus forge sentry; do
    if [ "$host" = "$(hostname -s)" ]; then
      if command -v nixos-rebuild-wrapper &>/dev/null; then
        log_success "Wrapper installed on $host (local)"
      else
        log_error "Wrapper NOT installed on $host (local)"
      fi
    else
      if ssh $host "command -v nixos-rebuild-wrapper" &>/dev/null; then
        log_success "Wrapper installed on $host"
      else
        log_error "Wrapper NOT installed on $host"
      fi
    fi
  done
}

# Check 2: Test Colmena evaluation
check_colmena_eval() {
  section "Colmena Evaluation Check"

  cd /etc/nixos
  log_info "Testing Colmena evaluation..."

  if nix run .#apps.x86_64-linux.colmena -- eval --nodes &>/dev/null; then
    log_success "Colmena can evaluate cluster configuration"
  else
    log_error "Colmena evaluation failed"
    return 1
  fi
}

# Check 3: Verify GPU scheduler state file
check_gpu_scheduler() {
  section "GPU Scheduler State Check"

  for host in zephyr nexus forge; do
    if ssh $host "test -f /run/gpu-scheduler/ai-state"; then
      log_success "GPU scheduler state exists on $host"
    else
      log_warning "GPU scheduler state missing on $host (will be created on first deploy)"
    fi
  done
}
```

**Staged Rollout Testing Order:**

1. **Zephyr** (local, 2x NVIDIA GPUs)
   - Test wrapper locally
   - Verify GPU scheduler signaling
   - Test rollback

2. **Sentry** (remote, AMD GPU)
   - Test remote deployment
   - Verify no GPU scheduler signaling (AMD GPU)

3. **Nexus** (remote, 1x NVIDIA GPU)
   - Test NVIDIA GPU scheduling integration
   - Verify mining pause/resume

4. **Forge** (remote, 2x NVIDIA GPUs)
   - Test multi-GPU node
   - Verify all GPU nodes can deploy in parallel

---

### 8. Implementation Plan

**Phase 1: Wrapper & State Tracking (Week 1)**

Create files:
- `scripts/nixos-rebuild-wrapper` - Main wrapper script
- `modules/system/nixos-rebuild-wrapper.nix` - NixOS module
- `docs/plans/2026-03-11-ci-cd-refactoring-design.md` - This document

Test on Zephyr only.

**Phase 2: GitHub Actions Fixes (Week 1-2)**

Modify files:
- `.github/workflows/ci.yml`
  - Remove `continue-on-error: true` from lint jobs
  - Remove `--all-systems` flag from flake check
- `.github/workflows/deploy.yml`
  - Replace SSH commands with Colmena
  - Add GPU scheduler signaling
  - Unify mining service names
- `.github/workflows/cluster-status.yml` - NEW

Test on Sentry (no GPU conflicts).

**Phase 3: justfile Standardization (Week 2)**

Modify files:
- `justfile`
  - Standardize all deployments to use `colmena apply --on`
  - Add `status-cluster`, `watch-deploy`, `clean-deploy-state` commands
  - Fix `ci-local` to match CI behavior
- `scripts/pre-deploy-check.sh`
  - Add wrapper installation check
  - Add Colmena evaluation check

Test on Nexus (first NVIDIA GPU node).

**Phase 4: GPU Scheduling Integration (Week 2-3)**

Modify files:
- `scripts/nixos-rebuild-wrapper`
  - Add GPU node detection
  - Implement signaling to `/run/gpu-scheduler/ai-state`
- `scripts/k8s-gpu-scheduler.py`
  - Add `DEPLOY_IN_PROGRESS` state handling
  - Scale mining deployments on deploy signals
- `modules/mining/mining.nix`
  - Add `mining.target` systemd target

Test on Forge (multi-GPU node).

**Phase 5: Full Cluster Rollout (Week 3)**

1. Deploy wrapper to all nodes
2. Update GitHub Actions workflows
3. Update justfile on all nodes (via NFS, already synced)
4. Run full cluster deployment test
5. Monitor with `just watch-deploy`

---

### 9. Rollback Procedure

If the refactoring causes issues:

**Option 1: Bypass Wrapper**
```bash
# Use native nixos-rebuild directly
NIXOS_REBUILD_NATIVE=1 nixos-rebuild switch

# Or call it directly
sudo /run/current-system/sw/bin/nixos-rebuild switch
```

**Option 2: Revert Wrapper Module**
```bash
# Remove wrapper module from configuration
# On each node:
sudo nixos-rebuild switch --flake /etc/nixos#$(hostname)

# This removes the wrapper, restoring native nixos-rebuild
```

**Option 3: Git Revert**
```bash
# Revert to commit before wrapper
git revert <commit-hash>
just deploy
```

---

## Success Criteria

The refactoring is successful when:

1. **Consistency**
   - ✅ All deployment paths use Colmena
   - ✅ Linters fail CI on code quality issues
   - ✅ Mining services use unified `mining.target`

2. **Visibility**
   - ✅ `just watch-deploy` shows real-time status
   - ✅ GitHub Actions status workflow runs every 5 minutes
   - ✅ State files in `/run/nixos-deploy/` are accurate

3. **GPU Integration**
   - ✅ Deployments to NVIDIA nodes signal `/run/gpu-scheduler/ai-state`
   - ✅ Mining pauses/resumes correctly during deployments
   - ✅ No deployment conflicts with AI workloads

4. **Reliability**
   - ✅ All 4 nodes can deploy in parallel without conflicts
   - ✅ Failed deployments auto-rollback
   - ✅ Error aggregation shows all failures

---

## Open Questions

1. **Systemd target creation**: Should `mining.target` be created in Phase 1 or Phase 4?
   - **Recommendation**: Phase 4, after GPU scheduling integration

2. **State file retention**: How long should state files be kept?
   - **Recommendation**: 7 days (configurable in `clean-deploy-state`)

3. **Colmena timeout**: Should we add explicit timeouts to Colmena commands?
   - **Recommendation**: Yes, 30 minutes for builds, 15 for applies

---

## Appendix: GPU Inventory Reference

| Host | GPUs | GPU Type | Needs GPU Scheduling? |
|------|------|----------|----------------------|
| Zephyr | RTX 3060 Ti + RTX 3090 | NVIDIA | ✅ Yes |
| Nexus | RTX 3060 Ti | NVIDIA | ✅ Yes |
| Forge | 2x RTX 4060 | NVIDIA | ✅ Yes |
| Sentry | RX 5600 XT | AMD | ❌ No |

---

## Next Steps

1. **Review and approve** this design document
2. **Create implementation plan** using `writing-plans` skill
3. **Begin Phase 1** (wrapper development)
4. **Test on Zephyr** (local)
5. **Iterate** based on feedback
