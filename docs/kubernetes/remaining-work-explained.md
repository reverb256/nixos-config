# Remaining Kubernetes Improvement Items - Detailed Explanation

**Generated**: 2026-03-21
**Cluster Health**: 8.5/10 (stable, minor improvements possible)

---

## 1. Service Accounts for Non-System Pods

### What This Means

**Current State**: 20+ pods are using the `default` service account

**Why This Matters**:
- **Security**: Default SA often has more permissions than needed
- **RBAC**: Can't implement least-privilege access control
- **Audit**: Hard to track which workloads have which permissions

### Examples from Your Cluster

**Pods using default SA**:
```bash
ai-inference/grafana-5c8f6744dd-2snc9
ai-inference/n8n-b87d66945-svlb4
akash-cpu-test/nginx-test-*
akash-services/cloudflared-*
glitchtip/web-7944656db4-pq6r9
ingress-nginx/ingress-nginx-controller-f49c7fbdf-rkpjx
```

**Risk Level**: ⚠️ **MEDIUM**

### The Fix

**Step 1: Create dedicated service accounts**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: grafana-sa
  namespace: ai-inference
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: grafana-role
  namespace: ai-inference
rules:
  # Grant only what Grafana needs
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: grafana-rolebinding
  namespace: ai-inference
subjects:
  - kind: ServiceAccount
    name: grafana-sa
roleRef:
  kind: Role
  name: grafana-role
  apiGroup: rbac.authorization.k8s.io
```

**Step 2: Update deployment to use the SA**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: ai-inference
spec:
  template:
    spec:
      serviceAccountName: grafana-sa  # Add this line
      containers:
      - name: grafana
        image: grafana/grafana:latest
```

### Concrete Impact

**Without dedicated SA**:
- Grafana runs with default SA permissions
- If compromised, attacker has default SA access
- Can't restrict Grafana to specific resources

**With dedicated SA**:
- Grafana runs with minimal required permissions
- If compromised, attacker only gets configmap/secret access
- Clear audit trail of permissions

### Priority Order

1. **HIGH**: Externally exposed services (ingress-nginx, cloudflared, glitchtip)
2. **MEDIUM**: Internal services (grafana, n8n, akash services)
3. **LOW**: Test workloads (akash-cpu-test)

### Estimated Effort

- **Time**: 2-3 hours for all 20+ pods
- **Risk**: Low (can test on one pod first)
- **Impact**: Medium security improvement

---

## 2. Add Health Checks to Workloads

### What This Means

**Current State**: Many pods lack `livenessProbe` and `readinessProbe`

**Why This Matters**:
- **Liveness Probe**: Detects when app is deadlocked and needs restart
- **Readiness Probe**: Detects when app is not ready to receive traffic
- **Auto-healing**: Kubernetes can restart unhealthy pods automatically

### Examples from Your Cluster

**Pods WITHOUT health checks**:
```bash
# AI inference services
ai-inference/n8n-b87d66945-svlb4
ai-inference/qdrant-0
ai-inference/redis-5f97c4cd67-5rs7z

# Akash services
akash-services/akash-node-1-0
akash-services/cloudflared-*

# Monitoring
glitchtip/web-7944656db4-pq6r9
glitchtip/worker-867988cdc4-lw2sz
```

**Risk Level**: ⚠️ **MEDIUM** (for stateful services), **LOW** (for stateless)

### The Fix

**HTTP-based health check** (for web services):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: ai-inference
spec:
  template:
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:latest
        ports:
        - containerPort: 3000
        livenessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
```

**TCP socket health check** (for databases/cache):
```yaml
readinessProbe:
  tcpSocket:
    port: 6379
  initialDelaySeconds: 5
  periodSeconds: 10
livenessProbe:
  tcpSocket:
    port: 6379
  initialDelaySeconds: 15
  periodSeconds: 20
```

**Exec-based health check** (custom scripts):
```yaml
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - pgrep -f myprocess
  initialDelaySeconds: 30
  periodSeconds: 10
```

### Concrete Impact

**Without health checks**:
```
App hangs/deadlocks → Pod marked "Running" → Traffic sent to dead pod → Users see errors
```

**With health checks**:
```
App hangs/deadlocks → Liveness probe fails → Kubernetes restarts pod → App recovers
```

**Real-world example from your cluster**:
- **operator-inventory**: Had 140 restarts before we fixed the liveness probe
- **Now stable**: After we adjusted the probe settings

### Priority Order

1. **HIGH**: Stateful services (databases, message queues)
   - `ai-inference/redis` (if it's used as cache)
   - `ai-inference/qdrant` (vector database)

2. **MEDIUM**: User-facing services
   - `glitchtip/web` (error tracking)
   - `ai-inference/grafana` (monitoring dashboard)
   - `ai-inference/n8n` (workflow automation)

3. **LOW**: Internal services
   - `akash-services/*` (already have some monitoring)

### Common Health Check Endpoints

| Application | Health Check Path | Notes |
|--------------|-------------------|-------|
| Grafana | `/api/health` | Returns JSON |
| n8n | `/healthz` | Standard endpoint |
| Redis | TCP socket on port 6379 | No HTTP endpoint |
| Qdrant | `/metrics` | Prometheus metrics |
| Nginx | `/` or `/health` | Returns 200 OK |

### Estimated Effort

- **Time**: 4-6 hours for all critical workloads
- **Risk**: Medium (bad probes can cause restart loops)
- **Testing**: Required for each service
- **Impact**: High reliability improvement

---

## 3. Implement Pod Disruption Budgets

### What This Means

**Current State**: No pod disruption budgets (PDBs) defined

**Why This Matters**:
- **Voluntary disruptions**: Node maintenance, cluster upgrades, autoscaling
- **Data protection**: Prevents downtime during maintenance
- **Availability**: Ensures minimum replicas always running

### How PDBs Work

**Without PDB**:
```
Cluster upgrade → All pods evicted simultaneously → Service downtime
```

**With PDB**:
```
Cluster upgrade → Only 1 pod evicted at a time → Service stays up
```

### Examples from Your Cluster

**Services that need PDBs**:

```yaml
# ai-inference/grafana (monitoring dashboard)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: grafana-pdb
  namespace: ai-inference
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: grafana

---
# ai-inference/n8n (workflow automation)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: n8n-pdb
  namespace: ai-inference
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: n8n

---
# glitchtip/web (error tracking frontend)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: glitchtip-web-pdb
  namespace: glitchtip
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: web

---
# glitchtip/worker (error tracking backend)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: glitchtip-worker-pdb
  namespace: glitchtip
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: worker
```

### PDB Configuration Options

**Option 1: `minAvailable`**
```yaml
spec:
  minAvailable: 2  # At least 2 pods must be available
```

**Option 2: `maxUnavailable`**
```yaml
spec:
  maxUnavailable: 1  # At most 1 pod can be unavailable
```

**Choosing between them**:
- **Use `minAvailable`**: When you need guaranteed capacity
- **Use `maxUnavailable`**: When you allow some downtime during updates

### Concrete Impact

**Scenario: Node Maintenance**

**Without PDB**:
```
Admin drains nexus node → All pods on nexus evicted → Service unavailable until pods reschedule
```

**With PDB (minAvailable: 1)**:
```
Admin drains nexus node → Kubernetes evicts pods one at a time → Ensures 1 pod always running → No downtime
```

**Real-world example**:
- **mining pods**: Already have `priorityClassName: preemtible-mining`
- **Should add PDB**: `minAvailable: 1` to prevent total eviction

### Priority Order

1. **HIGH**: Critical user-facing services
   - `glitchtip/web` (error tracking - users need access)
   - `ai-inference/grafana` (monitoring - need visibility)

2. **MEDIUM**: Backend services
   - `glitchtip/worker` (can queue requests)
   - `ai-inference/n8n` (workflows can wait)

3. **LOW**: Internal tools
   - `akash-cpu-test/nginx-test` (test workloads)

### Testing PDBs

**Test voluntary disruption**:
```bash
# Simulate node drain (without actually draining)
kubectl cordon <node-name>  # Mark node unschedulable
kubectl get pods -o wide  # See where pods go
kubectl uncordon <node-name>  # Undo

# Check PDB status
kubectl get pdb -A
```

**Expected behavior**:
```
# With PDB
kubectl cordon nexus
# Pods on nexus stay running (respecting minAvailable)
# New pods scheduled to other nodes

# Without PDB
kubectl cordon nexus
# All pods on nexus evicted immediately
```

### Estimated Effort

- **Time**: 2-3 hours for all critical services
- **Risk**: Low (PDBs are safety mechanisms, not disruptive)
- **Impact**: High availability during maintenance

---

## Summary of Work Items

| Item | Priority | Effort | Risk | Impact |
|------|----------|--------|------|--------|
| **Service Accounts** | Medium | 2-3 hours | Low | Medium security improvement |
| **Health Checks** | Medium | 4-6 hours | Medium | High reliability improvement |
| **Pod Disruption Budgets** | Medium | 2-3 hours | Low | High availability improvement |

### Total Effort Estimate

- **Total Time**: 8-12 hours for all three items
- **Recommended Pace**: 1-2 items per week
- **Testing Required**: Yes (especially for health checks)

### Implementation Order

**Week 1**: Service accounts (lowest risk, quick wins)
**Week 2**: Health checks (requires testing per service)
**Week 3**: Pod disruption budgets (finish with availability)

---

## Quick Reference Commands

### Check current service accounts
```bash
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.serviceAccountName == "default") | "\(.metadata.namespace)/\(.metadata.name)"'
```

### Check current health probes
```bash
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].livenessProbe == null) | "\(.metadata.namespace)/\(.metadata.name)"'
```

### Check current PDBs
```bash
kubectl get pdb -A
```

### Test health probe impact
```bash
# Delete pod with bad probe
kubectl delete pod <pod-name> -n <namespace>

# Watch it restart
kubectl get pod <pod-name> -n <namespace> -w
```

---

## Decision Framework

### Should You Implement These?

**Implement if**:
- ✅ Cluster runs production workloads
- ✅ Multiple users depend on services
- ✅ You need to perform node maintenance
- ✅ Security/compliance requirements exist

**Can skip if**:
- ❌ Cluster is only for development/testing
- ❌ You don't care about brief downtime during maintenance
- ❌ Workloads are ephemeral/throwaway

---

**Last Updated**: 2026-03-21
**Cluster**: 4-node NixOS Kubernetes cluster
**Current Health**: 8.5/10 (stable)
