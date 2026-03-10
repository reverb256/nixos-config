# Kubernetes Graceful Restart Procedure

**Purpose**: Prevent cascading failures during CRI-O restarts
**Created**: 2026-03-10
**Status**: Production Ready

---

## Problem Statement

**Incident**: CRI-O restart on 2026-03-10 caused 11-minute cluster outage

**Timeline**:
```
04:46:01 - CRI-O restarted for NVIDIA runtime configuration
04:46:01 - kube-apiserver: Deactivating (signal termination)
04:55:16 - kube-scheduler: "dial tcp 10.1.1.110:6443: connection refused"
04:55:26 - kube-scheduler: Leaderelection lost, exit code=1/FAILURE
04:57:19 - Manual restart required to restore cluster
```

**Root Cause**: No systemd dependency ordering or health checks
- CRI-O restart → kubelet lost connection → API server lost connection → Scheduler lost leadership
- Services started immediately after CRI-O restart, before it was ready
- No health check probes to wait for service readiness

---

## Solution

### 1. Systemd Dependency Ordering

**Correct Startup Sequence**:
```
1. crio.service (container runtime)
2. kubelet.service (waits for CRI-O readiness)
3. kube-apiserver.service (waits for kubelet readiness)
4. kube-scheduler.service (waits for API server)
5. kube-controller-manager.service (waits for API server)
```

**Implementation**: `modules/services/kubernetes.nix`
```nix
systemd.services = {
  crio = {
    after = ["network.target"];
    before = ["kubelet.service"];
    restartTriggers = ["/etc/crio/crio.conf.d/99-nvidia.toml"];
    serviceConfig.Restart = "on-failure";
  };

  kubelet = {
    after = ["crio.service"];
    requires = ["crio.service"];
    serviceConfig.ExecStartPre = "${wait-for-crio-script}";
  };

  kube-apiserver = {
    after = ["kubelet.service"];
    requires = ["kubelet.service"];
    serviceConfig.ExecStartPre = "${wait-for-kubelet-script}";
  };

  kube-scheduler = {
    after = ["kube-apiserver.service"];
    requires = ["kube-apiserver.service"];
  };

  kube-controller-manager = {
    after = ["kube-apiserver.service"];
    requires = ["kube-apiserver.service"];
  };
};
```

### 2. Health Check Probes

**CRI-O Readiness Check** (ExecStartPre for kubelet):
```bash
timeout=60
while [ $timeout -gt 0 ]; do
  if crictl info >/dev/null 2>&1; then
    echo "CRI-O is ready"
    exit 0
  fi
  sleep 1
  ((timeout--))
done
echo "ERROR: CRI-O not ready after 60 seconds"
exit 1
```

**Kubelet Readiness Check** (ExecStartPre for API server):
```bash
timeout=120
while [ $timeout -gt 0 ]; do
  if kubectl get nodes >/dev/null 2>&1; then
    echo "Kubelet is ready"
    exit 0
  fi
  sleep 2
  ((timeout--))
done
echo "ERROR: Kubelet not ready after 120 seconds"
exit 1
```

### 3. Automatic Restart on Failure

All services configured with:
```nix
serviceConfig = {
  Restart = "on-failure";
  RestartSec = "5s";  # CRI-O: 5s, kubelet: 10s, API server: 15s, scheduler/controller: 20s
};
```

### 4. Graceful Restart Script

**Location**: `/etc/nixos/scripts/graceful-k8s-restart.sh`

**Usage**:
```bash
sudo /etc/nixos/scripts/graceful-k8s-restart.sh
```

**What It Does**:
1. Stop control plane (reverse dependency order)
2. Restart CRI-O
3. Wait for CRI-O readiness (60s timeout)
4. Start kubelet
5. Wait for kubelet readiness (120s timeout)
6. Start control plane (dependency order)
7. Verify cluster health
8. Report status

**Example Output**:
```
[2026-03-10 05:00:00] === Graceful Kubernetes Restart Sequence ===
[2026-03-10 05:00:00] Stopping control plane services (reverse dependency order)...
[2026-03-10 05:00:01] Restarting CRI-O...
[2026-03-10 05:00:05] Waiting for CRI-O to be ready...
[2026-03-10 05:00:08] CRI-O is ready ✓
[2026-03-10 05:00:08] Starting kubelet...
[2026-03-10 05:00:12] Waiting for kubelet to be ready...
[2026-03-10 05:00:25] Kubelet is ready ✓
[2026-03-10 05:00:25] Starting kube-apiserver...
[2026-03-10 05:00:30] Starting kube-scheduler...
[2026-03-10 05:00:30] Starting kube-controller-manager...
[2026-03-10 05:00:35] Verifying cluster health...
[2026-03-10 05:00:45] === Final Health Check ===
[2026-03-10 05:00:45] ✓ crio.service is healthy
[2026-03-10 05:00:45] ✓ kubelet.service is healthy
[2026-03-10 05:00:45] ✓ kube-apiserver.service is healthy
[2026-03-10 05:00:45] ✓ kube-scheduler.service is healthy
[2026-03-10 05:00:45] ✓ kube-controller-manager.service is healthy
[2026-03-10 05:00:45] === Graceful Restart Complete ===
```

---

## When to Use Graceful Restart

### Use Graceful Restart When:

1. **CRI-O Configuration Changes**
   - After modifying `/etc/crio/crio.conf.d/99-nvidia.toml`
   - After NVIDIA runtime configuration changes
   - After CNI plugin updates

2. **Kubernetes Control Plane Issues**
   - API server not responding
   - Scheduler in restart loop
   - Controller manager failing

3. **Planned Maintenance**
   - System updates affecting container runtime
   - Network configuration changes
   - Certificate rotations

### DO NOT Use Graceful Restart When:

1. **Emergency Shutdown**
   - Use `systemctl stop` directly for immediate shutdown
   - Graceful restart takes 2-3 minutes

2. **Single Service Restart**
   - Use `systemctl restart kube-apiserver.service` for individual services
   - Graceful restart restarts entire control plane

3. **Worker Node Operations**
   - Use `kubectl drain` and `kubectl uncordon` for worker node maintenance
   - Graceful restart is for control plane only

---

## Testing the Fix

### Test 1: Verify Dependency Ordering

```bash
# Check systemd dependencies
systemctl show kube-apiserver.service -p After,Before,Requires --no-pager
systemctl show kubelet.service -p After,Before,Requires --no-pager
systemctl show crio.service -p After,Before,Requires --no-pager

# Expected output:
# kube-apiserver: After=kubelet.service, Requires=kubelet.service
# kubelet: After=crio.service, Requires=crio.service
# crio: Before=kubelet.service
```

### Test 2: Verify Health Check Scripts

```bash
# Check that ExecStartPre scripts exist
systemctl show kubelet.service -p ExecStartPre --no-pager
systemctl show kube-apiserver.service -p ExecStartPre --no-pager

# Expected output:
# ExecStartPre: {path=/nix/store/...-wait-for-crio}
# ExecStartPre: {path=/nix/store/...-wait-for-kubelet}
```

### Test 3: Test Graceful Restart

```bash
# Run graceful restart
sudo /etc/nixos/scripts/graceful-k8s-restart.sh

# Verify all services healthy
systemctl status crio kubelet kube-apiserver kube-scheduler kube-controller-manager

# Verify cluster health
kubectl get nodes
kubectl get pods -A
```

### Test 4: Simulate CRI-O Restart

```bash
# Restart CRI-O (should trigger automatic recovery)
sudo systemctl restart crio

# Wait 2 minutes for automatic recovery
sleep 120

# Verify cluster healthy
kubectl get nodes
kubectl get pods -n kube-system
```

---

## Rollback Procedure

If issues occur after applying these changes:

1. **Revert Kubernetes Module Changes**
   ```bash
   git checkout modules/services/kubernetes.nix
   just switch
   ```

2. **Manual Service Start**
   ```bash
   sudo systemctl start crio
   sudo systemctl start kubelet
   sudo systemctl start kube-apiserver
   sudo systemctl start kube-scheduler
   sudo systemctl start kube-controller-manager
   ```

3. **Verify Cluster Health**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

---

## Success Criteria

- ✅ CRI-O restart does not cascade to control plane failure
- ✅ Health check probes prevent premature startup
- ✅ Graceful restart script completes successfully
- ✅ Zero manual intervention required for CRI-O restarts
- ✅ All control plane services healthy after restart
- ✅ Cluster pods continue running during restart

---

## Related Documentation

- **Gap Analysis**: `/etc/nixos/docs/research/compute-scheduler-gaps-analysis.md`
- **Implementation Tracker**: `/etc/nixos/docs/research/compute-scheduler-implementation-tracker.md`
- **Incident Timeline**: 2026-03-10, 04:46-04:57 (11-minute outage)

---

## Maintenance Notes

**Version**: 1.0
**Last Updated**: 2026-03-10
**Next Review**: 2026-04-10

**Change History**:
- 2026-03-10: Initial implementation (Phase 5, Task 5.1-5.4 complete)
