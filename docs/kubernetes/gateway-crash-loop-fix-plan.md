# Gateway Crash Loop Fix Plan

**Created:** 2026-03-25 23:20
**Status:** READY TO IMPLEMENT
**Priority:** CRITICAL (blocking all MCP functionality)

---

## Problem Statement

**CRITICAL ISSUE:** AI Inference Gateway pods are crash-looping
- Pods show `Running` but `READY 0/1` (containers restarting)
- Health endpoint times out (application hangs)
- Logs show "Application startup complete" appearing multiple times = restart loop
- Caddy returns 503 Service Unavailable (no healthy backend pods)

**Root Cause Analysis:**
1. **Hermes memory directory permission error**: `[Errno 13] Permission denied: '/var/lib'`
2. **kubectl binary not found**: ConfigMap lookups failing during initialization
3. **Possible Python import errors**: Application might be hanging on import

**Impact:**
- ❌ MCP Gateway Bridge cannot connect
- ❌ Knowledge Fabric skill completely broken
- ❌ SearXNG MCP server non-functional
- ❌ All AI inference gateway features down

---

## Current State

### Gateway Pods Status
```
NAME                                    READY   STATUS    RESTARTS   AGE   NODE
ai-inference-gateway-5b885dd98c-rh8n8   0/1     Running   0          4m    nexus
ai-inference-gateway-75755d8b4b-kxsqw   0/1     Running   0          70s   nexus
ai-inference-gateway-75755d8b4b-k2kfl   0/1     Terminating   0          5h    nexus
```

### Gateway Service Endpoints
```
NAME                   ENDPOINTS   AGE
ai-inference-gateway   <none>      3d12h
```

**No healthy endpoints = 503 errors**

### DNS Configuration (✅ FIXED)
```
ai.cluster.local → 10.1.1.120, 10.1.1.130, 10.1.1.140 (Caddy nodes)
.mcp.json: "GATEWAY_URL": "http://ai.cluster.local" ✅
```

---

## Root Cause Analysis

### Issue 1: Hermes Memory Directory Permission Denied
```
Cannot create hermes memory directory: [Errno 13] Permission denied: '/var/lib'
```

**Problem:** Gateway tries to create `/var/lib/hermes` but lacks permissions
- Container runs as `runAsUser: 1000` (non-root)
- `/var/lib` is owned by root with restricted permissions
- Security context: `readOnlyRootFilesystem: false`

**Impact:** Blocks hermes memory system initialization

### Issue 2: kubectl Binary Not Found
```
✗ Failed to get ConfigMap: [Errno 2] No such file or directory: 'kubectl'
Failed to initialize scheduler comms: [Errno 2] No such file or directory: 'kubectl'
```

**Problem:** Container image doesn't include kubectl binary
- Gateway tries to lookup ConfigMaps via kubectl
- Fails silently but causes initialization delays
- May cause worker processes to hang

**Impact:** Blocks cluster integration features

### Issue 3: Possible Python Import/Module Error
**Observation:** Health endpoint times out, app restarts
- "Application startup complete" appears repeatedly
- Uvicorn with `--workers 4` creates 4 worker processes
- If workers crash on startup, they restart immediately

**Hypothesis:**
- Knowledge Fabric middleware imports failing
- Missing dependencies causing import errors
- circular import or deadlock during initialization

---

## Solution Architecture

### Phase 1: Immediate Fixes (Container Image)

**Task 1.1: Add kubectl to Container Image**
- File: `pkgs/ai-inference-gateway-image/default.nix`
- Action: Add `kubectl` to `gatewayPython` packages
- Rationale: ConfigMap lookups require kubectl binary

**Task 1.2: Fix Hermes Memory Directory**
- File: `modules/services/ai-inference/ai_inference_gateway/main.py` or config
- Action: Change hermes path to writable directory (`/run/ai-inference/hermes`)
- Rationale: Container runs as non-root, cannot write to `/var/lib`

**Task 1.3: Add Debug Logging to Startup**
- File: Gateway entrypoint or middleware initialization
- Action: Add try-except blocks with detailed logging
- Rationale: Identify exact point of failure during startup

### Phase 2: Test Minimal Gateway (Without Knowledge Fabric)

**Task 2.1: Create Diagnostic Deployment**
- File: `kubernetes-manifests/ai-inference/gateway-deployment-diagnostic.yaml`
- Action: Disable Knowledge Fabric middleware (`MIDDLEWARE__KNOWLEDGE_FABRIC__ENABLED=false`)
- Rationale: Isolate whether Knowledge Fabric is causing crash

**Task 2.2: Deploy and Test Diagnostic Version**
- Command: `kubectl apply -f gateway-deployment-diagnostic.yaml`
- Test: Check if pods become Ready
- Expected: Pods reach READY 1/1 if Knowledge Fabric is the issue

**Task 2.3: If Diagnostic Succeeds**
- Root cause: Knowledge Fabric middleware
- Action: Fix middleware initialization (see Phase 3)

**Task 2.4: If Diagnostic Fails**
- Root cause: Base gateway application
- Action: Check Python dependencies, imports, and uvicorn configuration

### Phase 3: Fix Knowledge Fabric Middleware

**Task 3.1: Lazy Import Knowledge Fabric Dependencies**
- File: `modules/services/ai-inference/ai_inference_gateway/middleware/knowledge_fabric/`
- Action: Move imports inside functions (lazy loading)
- Rationale: Avoid import errors during startup

**Task 3.2: Add Timeout to Initialization**
- File: Knowledge Fabric middleware `__init__`
- Action: Add timeouts to all external service connections
- Rationale: Prevent hangs during ConfigMap/SearXNG lookups

**Task 3.3: Graceful Degradation**
- Action: If Knowledge Fabric fails to initialize, log error but continue
- Rationale: Gateway should remain available even if optional features fail

### Phase 4: Kubernetes Configuration Fixes

**Task 4.1: Remove Hardcoded nodeName**
- File: `kubernetes-manifests/ai-inference/gateway-deployment.yaml`
- Action: Remove `nodeName: nexus` from pod template
- Rationale: Allows scheduling on any node (HA)

**Task 4.2: Add Resource Limits Validation**
- Action: Ensure pod fits on nexus with current resource usage
- Current: Requests 500m CPU / 512Mi RAM (should fit)

**Task 4.3: Check Tolerations and Node Affinity**
- Action: Ensure gateway can run on all nodes (not just nexus)

### Phase 5: Validation and Testing

**Task 5.1: Deploy Fixed Gateway**
- Action: Rebuild container image with fixes
- Command: `just deploy zephyr` (rebuilds and pushes image)

**Task 5.2: Verify Pod Health**
- Command: `kubectl get pods -n ai-inference -l app=ai-inference-gateway`
- Expected: READY 1/1, RESTARTS = 0

**Task 5.3: Test Health Endpoint**
- Command: `curl http://ai.cluster.local/health`
- Expected: `200 OK`

**Task 5.4: Test MCP Gateway Bridge**
- Command: `timeout 15 mcp-gateway-bridge ping_searxng`
- Expected: Successful ping

**Task 5.5: Test Knowledge Fabric Skill**
- Action: Use `/knowledge-fabric` skill with test query
- Expected: Search results returned

---

## Implementation Order

### Step 1: Quick Diagnostic (5 minutes) ✅ COMPLETE
1. ✅ Created diagnostic deployment without Knowledge Fabric
2. ✅ Deployed and observed pods become ready
3. ✅ **DECISION POINT REACHED:** Diagnostic works → Knowledge Fabric is the root cause

**Diagnostic Results (2026-03-25 23:30 UTC):**
- **Diagnostic Deployment:** ✅ READY 1/1, 0 restarts, 87 seconds to ready
- **Production Deployment:** ❌ READY 0/1, crash loop (Knowledge Fabric enabled)
- **Conclusion:** Knowledge Fabric middleware is causing the crash loop
- **Next Action:** Proceed directly to Phase 3 (Knowledge Fabric fixes)

### Step 2: Base Container Fixes (15 minutes)
1. Add kubectl to container image
2. Fix hermes memory directory path
3. Add debug logging
4. Rebuild and deploy

### Step 3: Knowledge Fabric Fixes (20 minutes)
1. Implement lazy imports
2. Add initialization timeouts
3. Add graceful degradation
4. Rebuild and deploy

### Step 4: Remove nodeName Constraint (5 minutes)
1. Update gateway deployment manifest
2. Apply to cluster

### Step 5: End-to-End Testing (10 minutes)
1. Verify pod health
2. Test MCP gateway bridge
3. Test Knowledge Fabric skill
4. Verify all search endpoints working

---

## Success Criteria

✅ **Gateway Pods Healthy:**
- All pods show READY 1/1
- Zero restarts
- Health endpoint returns 200 OK
- Endpoints populated in service

✅ **MCP Integration Working:**
- `mcp-gateway-bridge ping_searxng` succeeds
- Knowledge Fabric skill returns search results
- No 500 errors from SearXNG integration

✅ **DNS Configuration Stable:**
- `ai.cluster.local` resolves correctly
- Caddy routing working
- No hardcoded IPs in configuration

✅ **Documentation Updated:**
- CLAUDE.md DNS naming convention documented
- Incident report created
- Configuration fixes documented

---

## Rollback Plan

**If gateway still crashes after Phase 1:**
- Revert to last known working container image
- Check git history for `pkgs/ai-inference-gateway-image/default.nix`
- Identify what changes broke the gateway

**If Knowledge Fabric is the root cause:**
- Keep it disabled temporarily
- File incident report with specific error
- Plan separate fix for Knowledge Fabric middleware

**If nodeName removal causes issues:**
- Restore `nodeName: nexus` constraint
- Investigate why pods can't schedule on other nodes
- Check node resources, taints, and labels

---

## Testing Checklist

### Phase 1: Diagnostic
- [ ] Create gateway-deployment-diagnostic.yaml (Knowledge Fabric disabled)
- [ ] Apply diagnostic deployment
- [ ] Observe pod status for 2 minutes
- [ ] Check if pods reach READY 1/1
- [ ] Review pod logs for errors

### Phase 2: Container Image
- [ ] Add kubectl to gatewayPython packages
- [ ] Change hermes path to /run/ai-inference/hermes
- [ ] Add startup debug logging
- [ ] Rebuild container image
- [ ] Deploy updated image

### Phase 3: Knowledge Fabric
- [ ] Implement lazy imports in middleware
- [ ] Add initialization timeouts
- [ ] Add graceful degradation on init failure
- [ ] Test with Knowledge Fabric re-enabled

### Phase 4: K8s Configuration
- [ ] Remove nodeName constraint from deployment
- [ ] Verify resource limits
- [ ] Apply updated deployment

### Phase 5: End-to-End
- [ ] All gateway pods READY 1/1
- [ ] `curl http://ai.cluster.local/health` returns 200
- [ ] `mcp-gateway-bridge ping_searxng` succeeds
- [ ] Knowledge Fabric `/knowledge-fabric` test works
- [ ] SearXNG searches return results
- [ ] No crash loops in logs

---

## Time Estimate

- Phase 1 (Diagnostic): 5 minutes
- Phase 2 (Base Fixes): 15 minutes
- Phase 3 (Knowledge Fabric): 20 minutes
- Phase 4 (K8s Config): 5 minutes
- Phase 5 (Testing): 10 minutes

**Total: 55 minutes**

---

## Next Steps

**READY TO IMPLEMENT:** Start with Phase 1 diagnostic deployment to isolate whether Knowledge Fabric middleware is the root cause.

**Decision Point:** Based on diagnostic results, either:
- **Path A:** Fix Knowledge Fabric middleware (if diagnostic succeeds)
- **Path B:** Fix base container image issues (if diagnostic also fails)

**Question for User:** Should I proceed with Phase 1 (create diagnostic deployment) to isolate the root cause?

