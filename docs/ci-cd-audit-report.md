# CI/CD Infrastructure Audit Report

**Date:** 2026-03-11
**Audited by:** Claude Code Agent
**Scope:** GitHub Actions workflows, justfile, helper scripts

## Executive Summary

Overall CI/CD infrastructure is **functional but has consistency issues**. The main problems are:
1. **Inconsistent deployment methods** (SSH vs Colmena)
2. **Linter failures silently ignored**
3. **No GPU scheduling integration** during deployments
4. **Duplicate validation logic** across multiple systems

**Severity Breakdown:**
- Critical: 0
- High: 1
- Medium: 6
- Low: 2

---

## GitHub Actions Workflows

### 1. ci.yml - Pull Request Validation

**Jobs:**
- `quick-check`: Nix flake validation ✅
- `lint`: Statix + deadnix (with `continue-on-error: true`) ⚠️
- `security`: OSV scanner with SARIF upload ✅
- `build`: Builds all host configs on self-hosted runner ✅

**Issues:**

#### MEDIUM: Line 34 - Wasteful cross-platform builds
```yaml
run: nix flake check --all-systems  # Builds aarch64 unnecessarily
```
**Impact:** CI takes 2-3x longer than needed
**Fix:** Use `nix flake check` without `--all-systems` flag

#### HIGH: Lines 54, 58 - Silent linter failures
```yaml
- name: Run statix
  run: nix shell nixpkgs#statix --command statix check .
  continue-on-error: true  # ❌ Accepts bad code silently
```
**Impact:** PRs can merge with code quality issues
**Fix:** Remove `continue-on-error: true` or use warning-only mode

#### MEDIUM: Lines 111-115 - Hardcoded profile paths
```yaml
if [ ! -f "/nix/var/nix/profiles/system-$host" ]; then
```
**Impact:** Brittle verification that may fail with Nix changes
**Fix:** Use Colmena's built-in build output verification

---

### 2. deploy.yml - Production Deployment

**Good:**
- ✅ Pre-deploy validation script
- ✅ Mining pause/resume automation
- ✅ Health check after deployment
- ✅ Error aggregation (reports all failures)
- ✅ Manual workflow dispatch with target selection

**Issues:**

#### HIGH: Line 62 - Direct SSH bypasses Colmena
```bash
ssh $host "sudo nixos-rebuild switch --flake /etc/nixos#$host"
# ❌ Bypasses Colmena's dependency management
```
**Impact:** Inconsistent with justfile deployment, missing dependency checks
**Fix:** Use `nix run .#apps.x86_64-linux.colmena -- apply --on $host`

#### MEDIUM: Lines 39-40 - Hardcoded mining services
```bash
sudo systemctl stop xmrig@* || true
sudo systemctl stop lolminer-* || true
```
**Impact:** Doesn't match justfile which uses `lolminer-nvidia`
**Fix:** Use systemd target or service group

#### MEDIUM: Lines 114-125 - Limited health check
```bash
curl -f http://127.0.0.1:8080/health
```
**Impact:** Only checks AI gateway, not K8s, storage, or other services
**Fix:** Comprehensive health checks (K8s API, storage mounts, GPU status)

#### MEDIUM: No GPU scheduling integration
**Impact:** Deployments can conflict with active AI workloads
**Fix:** Write `DEPLOY_IN_PROGRESS` to `/run/gpu-scheduler/ai-state`

---

### 3. flake-update.yml - Dependency Updates

**Status:** Clean, no issues ✅

- ✅ Weekly schedule (Sundays at 3 AM)
- ✅ Automated PR creation
- ✅ Verification build before PR
- ✅ Auto-deletes branch after merge

---

## justfile - Local Automation

**Sections:**
1. **Deployment** (lines 14-135): ✅ Good
2. **Local Operations** (lines 141-172): ✅ Good
3. **Utilities** (lines 178-226): ✅ Good
4. **AI Inference** (lines 229-330): ✅ Excellent integration
5. **CI/CD** (lines 332-405): ✅ Well-designed
6. **Container Scanning** (lines 407-421): ✅ Security-focused

**Issues:**

#### LOW: Line 196 - Deprecated command still exists
```bash
# Sync all nodes to current branch (DEPRECATED - colmena handles this)
sync:
```
**Impact:** User confusion, dead code
**Fix:** Remove or repurpose for other sync operations

#### MEDIUM: Lines 342-348 - ci-local has same silent failures
```bash
statix check . || true       # ⚠️ Same silent failure issue
deadnix -f . || true         # ⚠️ Same silent failure issue
```
**Impact:** Local development doesn't catch lint issues
**Fix:** Match CI behavior (fail on lint errors)

#### LOW: Lines 412-421 - Container scanning Docker-only
```bash
scan-containers:
    trivy image --severity HIGH,CRITICAL $(docker ps --format '{{{{.Image}}}}')
```
**Impact:** Doesn't scan containerd/Kubernetes pods
**Fix:** Consolidate `scan-containers` and `scan-k8s` or clarify purpose

---

## Helper Scripts

### 1. pre-deploy-check.sh

**Status:** Excellent validation coverage ✅

**Checks Performed:**
- Git cleanliness ✅
- Flake validation ✅
- Agenix secrets ✅
- Distributed builds ✅
- Storage mounts ✅
- Build targets ✅
- Network connectivity ✅
- Mining status ✅

**Issues:**

#### MEDIUM: Line 67 - Skips build validation
```bash
nix flake check --no-build
```
**Impact:** Build errors only appear during actual deployment
**Fix:** Remove `--no-build` or add separate build check step

#### LOW: Lines 101-106 - Doesn't verify key validity
```bash
if [ ! -f "/home/j_kro/.age/key.txt" ] && [ ! -f "/root/.age/key.txt" ]; then
    log_warning "Age identity key not found"
```
**Impact:** Key exists but might not decrypt secrets
**Fix:** Attempt test decryption of a known secret

---

### 2. health-check.sh

**Status:** Basic but functional ⚠️

**Issues:**

#### MEDIUM: Line 13 - Only checks AI gateway
```bash
curl -f http://127.0.0.1:8080/health
```
**Impact:** No visibility into K8s, storage, GPU status
**Fix:** Add checks for:
- Kubernetes API (`kubectl get nodes`)
- Storage mounts (`mountpoint -q /data/@projects`)
- GPU status (`nvidia-smi` or equivalent)

---

### 3. local-ci.sh

**Status:** Good local CI mirroring ✅

Matches GitHub Actions CI structure well. No significant issues.

---

## Fish Shell Aliases

**Result:** None found in repository.

The only `.fish` file is `vllm-env/bin/activate.fish` (Python virtualenv activation).

---

## Summary of Issues

| Category | Critical | High | Medium | Low | Total |
|----------|----------|------|--------|-----|-------|
| GitHub Actions | 0 | 1 | 2 | 1 | 4 |
| justfile | 0 | 0 | 1 | 2 | 3 |
| Scripts | 0 | 0 | 2 | 1 | 3 |
| **Total** | **0** | **1** | **6** | **2** | **9** |

---

## Top 3 Recommended Fixes

### 1. Fix Deployment Inconsistency (HIGH)
**File:** `.github/workflows/deploy.yml:62`
**Change:** Use Colmena instead of direct SSH
**Reason:** Matches justfile behavior, proper dependency management

### 2. Make Linters Fail CI (MEDIUM)
**Files:** `.github/workflows/ci.yml:54,58` and `justfile:344,346`
**Change:** Remove `continue-on-error: true` and `|| true`
**Reason:** Prevents merging code with quality issues

### 3. Integrate GPU Scheduling (MEDIUM)
**File:** `.github/workflows/deploy.yml`
**Change:** Add GPU state signaling before/after deployment
**Reason:** Prevents deployment conflicts with active AI workloads

---

## Next Steps

See brainstorming session for CI/CD refactoring design addressing all identified issues.
