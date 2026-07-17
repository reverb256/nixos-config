# CoreDNS Production Troubleshooting Guide

**Sources**: K8s Official DNS Debugging Guide, CoreDNS Manual, Production Experience 2026  
**Last Updated**: 2026-03-27

## Phase 1: Verify CoreDNS Health (2 min)

### Step 1.1: Check CoreDNS Pod Status
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```
**Expected**: All pods `Running` with `1/1` READY  
**Failure**: If `0/1` or `CrashLoopBackOff` → jump to Phase 3

### Step 1.2: Verify DNS Service Exists
```bash
kubectl get svc -n kube-system kube-dns
```
**Expected**: `ClusterIP` matches pod `/etc/resolv.conf` nameserver  
**Failure**: Service missing or wrong IP → check Service/Endpoints

### Step 1.3: Check CoreDNS Logs
```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```
**Healthy Log Pattern**:
```
.:53
[INFO] CoreDNS-1.x.x
[INFO] plugin/reload: Running configuration MD5 = ...
```
**Failure Signs**: `SERVFAIL`, `loop detected`, connection errors → Phase 3

---

## Phase 2: Test DNS Resolution in Pods (3 min)

### Step 2.1: Create Debug Pod
```bash
kubectl run dns-debug --image=infoblox/dnstools:latest --rm -it --restart=Never -- bash
```

### Step 2.2: Verify Internal Service Resolution
```bash
# Inside debug pod:
nslookup kubernetes.default.svc.cluster.local
dig kubernetes.default.svc.cluster.local
```
**Expected**: Returns ClusterIP (e.g., `10.96.0.1`)  
**Failure**: `NXDOMAIN` or timeout → Phase 3

### Step 2.3: Test External DNS Resolution
```bash
nslookup google.com
dig google.com
```
**Expected**: Returns A records  
**Failure**: `SERVFAIL` → check upstream DNS in CoreDNS ConfigMap

### Step 2.4: Check Pod DNS Configuration
```bash
cat /etc/resolv.conf
```
**Expected**:
```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```
**Common Issues**:
- Wrong `nameserver` IP → kubelet `--cluster-dns` flag misconfigured
- Missing `search` domains → kubelet `--cluster-domain` flag issue
- `ndots:5` missing → pods can't resolve short service names

---

## Phase 3: Common Failure Modes & Fixes

### Failure Mode 1: CoreDNS Pods Not Starting

**Symptoms**: `CrashLoopBackOff`, `0/1` READY

**Debug**:
```bash
# Check pod events
kubectl describe pod -n kube-system <coredns-pod-name>

# Check resource limits
kubectl top pods -n kube-system
```

**Common Causes**:
1. **RBAC permissions missing** (2026 common issue):
   ```bash
   kubectl describe clusterrole system:coredns -n kube-system
   # Must have: endpoints, namespaces, pods, services, endpointslices
   ```

2. **ConfigMap syntax error**:
   ```bash
   kubectl get configmap coredns -n kube-system -o yaml
   # Look for: indentation errors, missing plugins
   ```

3. **Resource limits exceeded**:
   ```bash
   kubectl describe pod -n kube-system <coredns-pod>
   # Check: Limits/CPU/Memory
   ```

### Failure Mode 2: DNS Forwarding Loop

**Symptoms**: CoreDNS logs show `loop detected`, DNS hangs

**Root Cause**: CoreDNS forwards to itself (circular reference)

**Fix**:
```bash
# Edit CoreDNS ConfigMap
kubectl -n kube-system edit configmap coredns

# Check forward plugin:
# ❌ WRONG (loop):
# forward . /etc/resolv.conf  # if /etc/resolv.conf points to CoreDNS

# ✅ CORRECT:
# forward . 8.8.8.8 9.9.9.9
# OR use upstream DNS directly
```

### Failure Mode 3: systemd-resolved Conflict (Ubuntu/Debian)

**Symptoms**: Intermittent DNS failures, `SERVFAIL` in logs

**Root Cause**: `/etc/resolv.conf` is stub file, causes forwarding loop

**Fix**:
```bash
# Check if systemd-resolved is active
ls -la /etc/resolv.conf
# If symlink to ../run/systemd/resolve/stub-resolv.conf → conflict

# Solution: Configure kubelet to use correct resolv.conf
# On each node:
kubelet --resolv-conf=/run/systemd/resolve/resolv.conf
```

### Failure Mode 4: Alpine Images DNS Failure (musl < 1.24)

**Symptoms**: DNS works in some pods, fails in Alpine-based pods

**Root Cause**: Alpine < 3.18 lacks TCP fallback for large DNS responses (>512 bytes)

**Fix**: Update base images to Alpine 3.18+ or use Debian/Ubuntu base

### Failure Mode 5: Missing Search Domains

**Symptoms**: `kubernetes` resolves, `kubernetes.default` fails

**Debug**:
```bash
# In debug pod:
nslookup kubernetes.default
# Fails with NXDOMAIN

nslookup kubernetes.default.svc.cluster.local
# Works
```

**Fix**: Check kubelet configuration on nodes:
```bash
# On node:
ps aux | grep kubelet
# Look for: --cluster-domain=cluster.local
```

### Failure Mode 6: CoreDNS Can't Reach Upstream DNS

**Symptoms**: Internal service resolution works, external fails

**Debug**:
```bash
# Test upstream DNS from CoreDNS pod:
kubectl exec -n kube-system <coredns-pod> -- nslookup google.com 8.8.8.8

# If fails: network policy or firewall blocking egress
```

**Fix**: Check network policies:
```bash
kubectl get networkpolicies -n kube-system
# Ensure CoreDNS pods can reach external DNS (53/UDP, 53/TCP)
```

---

## Phase 4: Advanced Diagnostics (5 min)

### Enable Query Logging (Temporary)
```bash
kubectl -n kube-system edit configmap coredns
```
Add `log` plugin to Corefile:
```yaml
data:
  Corefile: |
    .:53 {
        log          # ADD THIS LINE
        errors
        health
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          upstream
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
```
Wait 2 minutes for ConfigMap propagation, then:
```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100 | grep "A IN"
```

### Test Direct CoreDNS Endpoint
```bash
# Get CoreDNS pod IP
COREDNS_POD_IP=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].status.podIP}')

# Test DNS directly (bypass service)
kubectl run test-direct --image=busybox --rm -it --restart=Never -- \
  nslookup kubernetes.default $COREDNS_POD_IP
```
**If direct works but service fails** → Service/Endpoints issue  
**If both fail** → CoreDNS configuration issue

### Check Endpoints
```bash
kubectl get endpoints kube-dns -n kube-system
```
**Expected**: Lists CoreDNS pod IPs  
**Failure**: Empty list → CoreDNS pods not ready or selector mismatch

---

## Phase 5: Production-Specific Checks

### 1. Check Node DNS Configuration
```bash
# On each node:
cat /etc/resolv.conf
# Ensure NOT using systemd-resolved stub if kubelet not configured for it
```

### 2. Verify kubelet DNS Flags
```bash
# On node:
ps aux | grep kubelet | grep -E 'cluster-dns|cluster-domain'
# Expected: --cluster-dns=<service-ip> --cluster-domain=cluster.local
```

### 3. Check for DNS Rate Limiting
```bash
# CoreDNS metrics (if prometheus enabled)
kubectl port-forward -n kube-system svc/kube-dns 9153:9153 &
curl http://localhost:9153/metrics | grep coredns_cache
```

### 4. Verify Network Policies
```bash
# Check if policies block CoreDNS
kubectl get networkpolicies --all-namespaces
# Look for: egress rules blocking port 53
```

---

## Quick Reference: Common Commands

```bash
# Full health check (run all):
kubectl get pods,svc,endpoints -n kube-system -l k8s-app=kube-dns

# DNS resolution test:
kubectl run test --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default

# CoreDNS ConfigMap:
kubectl get configmap coredns -n kube-system -o yaml

# CoreDNS RBAC:
kubectl describe clusterrole system:coredns

# Check kubelet DNS config (on node):
ps aux | grep kubelet | grep -o '\-\-cluster-dns=[^ ]*'
```

---

## Known Issues (2026)

1. **Alpine < 3.18**: DNS fails for large responses → upgrade to 3.18+
2. **Ubuntu systemd-resolved**: Forwarding loop → configure kubelet `--resolv-conf`
3. **glibc nameserver limit**: Max 3 nameservers → use dnsmasq or reduce entries
4. **Calico/Cilium CNI**: May require explicit DNS egress policies

---

## Decision Tree

```
DNS fails in pod
├─ CoreDNS pods running?
│  ├─ No → Check RBAC, ConfigMap, resources (Phase 3.1)
│  └─ Yes → Test internal service resolution
│     ├─ Works → External DNS issue → Check forward plugin (Phase 3.2)
│     └─ Fails → Check /etc/resolv.conf in pod
│        ├─ Wrong nameserver → kubelet --cluster-dns flag
│        ├─ Missing search → kubelet --cluster-domain flag
│        └─ Correct → Enable logging, check CoreDNS logs (Phase 4)
```

---

**Next Steps**: 
1. Run Phase 1 commands (2 min)
2. If all healthy, run Phase 2 tests (3 min)
3. Based on failure, jump to specific Phase 3 section
4. If unresolved, enable logging and run Phase 4 diagnostics
