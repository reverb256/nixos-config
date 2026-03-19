# Istio Service Mesh Deployment - Status & Challenges

**Date:** 2026-03-18
**Status:** Partial - Control plane running, sidecar injection issues remain

## Current State

### ✅ Istio Control Plane
- **istiod**: Running on sentry (10.244.2.15)
- **CRDs**: All 14 Istio CRDs installed
- **Mesh Resources**: PeerAuthentication, DestinationRule, ServiceEntry, AuthorizationPolicy created
- **Namespace**: ai-inference has istio-injection: enabled

### ⚠️ Sidecar Injection Issues
- **Problem**: Init container istio-proxy fails with readiness probe timeout
- **Error**: `Get "http://10.244.x.x:15021/healthz/ready": connection refused`
- **Root Cause**: Likely related to NixOS networking + Flannel CNI interaction
- **Impact**: Pods cannot be deployed with Istio sidecars

### ✅ Working Components (Non-Istio)
- **llama.cpp**: Optimized for Qwen3.5 with Flash Attention, parallel decoding, KV cache quantization
- **AI Gateway**: Running with graceful degradation (llama.cpp → vLLM → sglang → ZAI API)
- **NVIDIA Device Plugin**: Deployed and working (2 GPUs on Zephyr, 1 on Forge, 1 on Nexus)
- **Observability**: Prometheus and Grafana deployed
- **Networking**: Flannel CNI (NixOS-managed) + kube-proxy (systemd) working on Zephyr

### ⚠️ Istio Deployment Challenges

#### 1. Sidecar Injection Init Container Failure (NEW)
**Issue:** istio-proxy init container fails readiness probe
```
Get "http://10.244.x.x:15021/healthz/ready": connection refused
```
**Impact:** Pods with Istio sidecars stuck in Init:1/2 state
**Root Cause:** NixOS networking + Flannel CNI interaction with Istio proxy
**Attempted Fixes:**
- Disabled holdApplicationUntilProxyStarts
- Set PERMISSIVE mTLS mode
- Checked istiod connectivity (working)
**Status:** UNRESOLVED - requires deeper networking investigation

#### 2. CNI Configuration Conflicts (RESOLVED)
**Issue:** Multiple CNI plugins (Flannel, Cilium) causing conflicts
**Fix:** NixOS rebuild cleaned up CNI configuration
**Current State:** Flannel working on all nodes

#### 3. Read-Only File System (WORKAROUND)
**Issue:** `/etc/cni/net.d` is read-only (NixOS immutable store)
**Workaround:** Use NixOS rebuild for CNI changes

#### 4. Mutating Webhook Circular Dependency (RESOLVED)
**Issue:** Sidecar injector webhook tried to inject into istiod
**Fix:** Used hostNetwork for istiod deployment

#### 5. RBAC Permissions (RESOLVED)
**Issue:** istiod service account missing permissions
**Fix:** Added necessary permissions to ClusterRole

## Potential Solutions

### Option A: Fix CNI Configuration (Recommended)
1. Remove Cilium CNI config via NixOS configuration
2. Rebuild nodes to apply clean CNI setup
3. Re-deploy Istio with sidecar mode

### Option B: Use Istio Ambient Mode
1. Requires Cilium as base CNI
2. More complex setup but better performance
3. Replaces kube-proxy (but we have systemd kube-proxy)

### Option C: Delay Istio, Use Current Setup
1. Current setup is functional for AI inference
2. Graceful degradation working at application layer
3. Can add Istio later when networking is stable

## Current AI Inference Architecture

```
Client Request
     ↓
AI Gateway (port 8080, systemd)
     ↓
┌─────────────────────────────────────────────────────┐
│              Application Layer Circuit Breaker       │
│  ┌───────────────────────────────────────────────┐   │
│  │  Backend Health: llama.cpp (healthy)         │   │
│  │  Retry Policy: 3 attempts, exponential backoff │   │
│  │  Fallback: ZAI API (external)                  │   │
│  └───────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
     ↓
llama.cpp (port 8083)
  - Qwen3.5-2B with IQ4_NL quantization
  - Flash Attention, parallel decoding
  - KV cache: q8_0 (keys) / q4_0 (values)
  - Performance: ~81 tokens/sec
```

## Recommendations

### Immediate (Current Session)
1. ✅ **Istio control plane deployed** - istiod running
2. ✅ **Mesh resources created** - PeerAuthentication, DestinationRule, etc.
3. ⚠️ **Sidecar injection blocked** - Requires networking investigation

### Short-term (Next Sessions)
1. **Investigate sidecar injection** - Check CNI compatibility with Istio
2. **Test application-layer mesh** - Use Istio resources without sidecars
3. **Consider Istio Ambient mode** - Uses waypoint proxies instead of sidecars

### Long-term Options
1. **Linkerd** - Lighter weight, simpler sidecar model
2. **Cilium with eBPF** - Native service mesh capabilities
3. **Stay with application-layer** - Current circuit breaker is working well

## Files Created During Session

- `/etc/nixos/kubernetes-manifests/istio-zephyr.yaml` - Istio deployment manifest (not applied)
- `/etc/nixos/kubernetes-manifests/kube-proxy.yaml` - Unused (kube-proxy runs via systemd)

## Lessons Learned

1. **NixOS Kubernetes networking is unique** - systemd services, not DaemonSets
2. **CNI conflicts are hard to debug** - Multiple CNI plugins cause confusing errors
3. **Istio has complex dependencies** - Webhooks, CRDs, RBAC must all align
4. **hostNetwork bypasses CNI issues** - Useful for control plane components

## Success Criteria (Updated)

- [x] llama.cpp optimized and running
- [x] NVIDIA GPU device plugin deployed
- [x] Multi-backend AI Gateway with graceful degradation
- [x] Observability stack (Prometheus, Grafana)
- [x] Istio control plane (istiod) deployed and running
- [x] Istio CRDs installed (14 resources)
- [x] Mesh configuration created (PeerAuthentication, DestinationRule, etc.)
- [ ] Istio sidecar injection (blocked by init container issue)
- [ ] mTLS between services (PERMISSIVE mode active, STRICT pending sidecar fix)

## Istio Resources Deployed

```bash
# Control Plane
$ kubectl get pods -n istio-system
NAME                     READY   STATUS    RESTARTS   AGE
istiod-cd4667d86-4xxz7   1/1     Running   0          10m

# Mesh Resources
$ kubectl get peerauthentication -A
NAMESPACE      NAME                   MODE         AGE
ai-inference   ai-inference-mtls      PERMISSIVE   8m
istio-system   default                STRICT       8m

$ kubectl get destinationrule,serviceentry,authorizationpolicy -n ai-inference
NAME                              HOST         AGE
destinationrule.networking.istio.io/ai-gateway   ai-gateway   8m

NAME                                         HOSTS            LOCATION        AGE
serviceentry.networking.istio.io/llama-cpp-external   ["zephyr.lan"]   MESH_EXTERNAL   8m

NAME                                                   ACTION   AGE
authorizationpolicy.security.istio.io/ai-gateway-to-llamacpp   ALLOW   5m
```

## Next Steps for Istio

1. **Debug init container failure** - Check envoy proxy bootstrap process
2. **Consider ambient mesh** - Istio 1.22+ ambient mode doesn't use sidecars
3. **Alternative: Linkerd** - Simpler proxy model, better compatibility
4. **Or: Application-layer only** - Current circuit breaker is sufficient for many use cases
