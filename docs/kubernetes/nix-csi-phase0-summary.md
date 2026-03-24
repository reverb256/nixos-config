# Phase 0: nix-csi Driver - Status & Decision Points

**Date:** 2026-03-23
**Status:** ⚠️ Blocked on Build Complexity | ✅ Alternative Validated

---

## Executive Summary

**Goal:** Enable Kubernetes pods to access `/nix/store` for Nix package deployment

**Challenge:** nix-csi driver requires complex multi-arch build process (ARM64 + x86_64)

**Current Situation:** Phase 0 goals achievable via simpler approach, but with trade-offs

---

## Test Results: hostPath Alternative ✅

**What Works:**
- Direct hostPath mount to `/nix/store` (141,698 packages accessible)
- Read-only enforcement verified
- Suitable for privileged namespaces (kube-system)

**Limitations:**
- ❌ Violates PodSecurity "baseline" in standard namespaces
- ❌ Requires privileged containers
- ❌ Not production-ready for application workloads

**Test Evidence:**
```bash
$ kubectl logs nix-store-hostpath-test -n kube-system
Store entries: 141698
✅ Read-only mount verified
✅ /nix/store accessible
```

---

## nix-csi Driver Build Issues

### Problem 1: Multi-Arch Requirement
```
error: required system: 'aarch64-linux'
3 available machines: ([x86_64-linux], ...)
```

**Root Cause:** nix-csi project hardcodes both architectures in kubenix/options.nix
```nix
_module.args = {
  x86Pkgs = import nixpkgs { system = "x86_64-linux"; };
  armPkgs = import nixpkgs { system = "aarch64-linux"; };
};
```

### Problem 2: Missing Application Closure
Current manifest uses `scratch:1.0.1` image which lacks:
- `dinit` executable (init system)
- nix-csi Python application
- Complete Nix store closure

**Expected Behavior:**
1. Init container (lix image) populates `/nix-volume` with store paths
2. Main container (scratch image) runs `dinit` from `/nix/var/result/bin/`
3. CSI daemon handles volume mount requests

**Actual Behavior:**
```
exec: "dinit": executable file not found in $PATH
```

### Problem 3: Authentication Confusion ✅ RESOLVED
- **Initial assumption:** No GHCR/Docker Hub access
- **Reality:** Authentication was available all along
- **Evidence:** Successfully pushed scratch:1.0.1 to GHCR

---

## Decision Matrix

### Option A: Use hostPath (Fast, Limited Scope) ⚡

**Pros:**
- ✅ Works today for kube-system services
- ✅ Zero build complexity
- ✅ Simple to understand and debug

**Cons:**
- ❌ PodSecurity violations in standard namespaces
- ❌ Not suitable for production applications
- ❌ Security concerns (privileged access)

**Use Case:** System-level services in kube-system (monitoring, ingress)

**Implementation:**
```yaml
volumes:
- name: nix-store
  hostPath:
    path: /nix/store
    type: Directory
```

---

### Option B: Complete nix-csi Build (Production-Ready, Complex) 🔧

**Pros:**
- ✅ PSA-compliant /nix/store access
- ✅ Works in any namespace
- ✅ CSI ephemeral volumes (auto-cleanup)
- ✅ Production-grade solution

**Cons:**
- ❌ Multi-arch build complexity
- ❌ Requires ARM64 builders or code changes
- ❌ Steep learning curve for kubenix

**Use Case:** Production workloads requiring Nix packages

**Implementation Requirements:**
1. Fix multi-arch build (disable ARM or add builders)
2. Build complete nix-csi application closure
3. Deploy via kubenix deployment system

**Estimated Effort:** 4-8 hours (depending on ARM64 decision)

---

### Option C: Hybrid Approach (Pragmatic) 🎯

**Pros:**
- ✅ Immediate progress with hostPath
- ✅ Plan for nix-csi when needed
- ✅ Defer complexity until necessary

**Cons:**
- ❌ Two different deployment patterns
- ❌ Technical debt to address later
- ❌ Namespace restrictions remain

**Use Case:** Gradual migration, learning curve management

**Implementation:**
- Phase 0: Use hostPath for kube-system services
- Phase 1+: Deploy nix-csi for application namespaces

**Timeline:**
- Now: hostPath for system services
- Week 1-2: Evaluate if CSI driver needed
- Week 3+: Build nix-csi if application workloads require it

---

## Recommendations

### Short-Term (This Week)
1. **Use Option A (hostPath)** for kube-system services
2. Document PSA violations as known limitation
3. Monitor for actual /nix/store access needs

### Medium-Term (Next Sprint)
1. **Evaluate application requirements:**
   - Do non-privileged pods need /nix/store?
   - Can workloads run in kube-system?
   - Is CSI ephemeral volume capability needed?

2. **Decision point:**
   - If YES to above → Pursue Option B (build nix-csi)
   - If NO → Continue with Option A

### Long-Term (Q2 2026)
1. **If Option B chosen:**
   - Add ARM64 builders OR patch nix-csi to x86_64-only
   - Complete kubenix deployment
   - Migrate from hostPath to CSI

2. **If Option A sufficient:**
   - Document hostPath pattern in runbooks
   - Monitor for security issues
   - Re-evaluate quarterly

---

## Technical Debt & Risks

### Option A (hostPath) Risks
- **Security:** Privileged container escape surface
- **Compliance:** PodSecurity violations
- **Scalability:** Limited to kube-system namespace

### Option B (nix-csi) Risks
- **Complexity:** kubenix learning curve
- **Maintenance:** Custom build process
- **Debugging:** CSI driver complexity

### Option C (Hybrid) Risks
- **Inconsistency:** Two deployment patterns
- **Documentation:** More complex runbooks
- **Technical Debt:** Deferred complexity

---

## Next Actions

### Immediate (Choose One)
- [ ] **Option A:** Proceed with hostPath for Phase 0
- [ ] **Option B:** Invest time in nix-csi build process
- [ ] **Option C:** Adopt hybrid approach with evaluation period

### If Option B Chosen
1. Decide: Disable ARM64 OR add ARM64 builders
2. Build nix-csi-node-env package
3. Extract store paths from build
4. Update manifests with correct init container config
5. Deploy via kubenix or manual YAML

### If Option A Chosen
1. Document hostPath usage pattern
2. Label affected services with PSA exceptions
3. Monitor for security issues
4. Create migration plan for future

---

## Appendix: Build Commands Reference

### Check Available Images
```bash
curl -s "https://ghcr.io/v2/lillecarl/nix-csi/tags/list" | jq .
```

### Build nix-csi Locally (x86_64-only attempt)
```bash
cd /tmp/nix-csi
nix build --file . kubenixCI1.eval.config.kubenix.pkgs.nix-csi-node-env
```

### Deploy via kubenix (if build succeeds)
```bash
nix run --file . kubenixApply.deploymentScript -- --yes --prune
```

### Extract Store Paths (for manual deployment)
```bash
nix-store -qR result | grep nix-csi
```

---

**Document Owner:** j_kro
**Version:** 1.0
**Last Updated:** 2026-03-23 09:50 UTC
