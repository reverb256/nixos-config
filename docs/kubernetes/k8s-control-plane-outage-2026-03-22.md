# Kubernetes Control Plane Outage - 2026-03-22

**Date**: 2026-03-22
**Severity**: Critical (Complete Cluster Outage)
**Duration**: ~3 minutes (07:55:55 - 07:58:20 UTC)
**Root Cause**: kube-apiserver restart hung during shutdown phase

---

## Incident Timeline

### 07:55:55 UTC - Outage Begins
- `systemctl restart kube-apiserver.service` executed
- kube-apiserver began shutdown process
- kube-controller-manager stopped simultaneously
- kube-scheduler stopped simultaneously
- **Impact**: Kubernetes API server became unavailable

### 07:55:55 - 07:56:56 UTC - Hung Shutdown
- kube-apiserver stuck in "deactivating (stop-sigterm)" state
- API server stopped listening on port 6443
- All cluster operations failed
- kubectl commands: "Connection refused"

### 07:56:56 UTC - API Server Restarted
- Manually stopped hung shutdown: `systemctl stop kube-apiserver.service`
- Started API server: `systemctl start kube-apiserver.service`
- New kube-apiserver process started (PID 823541)
- API server began listening on port 6443

### 07:58:20 UTC - Full Recovery
- kube-controller-manager restarted
- kube-scheduler restarted
- All control plane components active
- Cluster operations resumed

---

## Root Cause Analysis

### Direct Cause
kube-apiserver restart command triggered a shutdown that hung for ~60 seconds. During this time:
- Old API server process (PID 671992) was shutting down
- Port 6443 was not listening
- kubelet couldn't renew leases (TLS certificate errors)
- All cluster operations failed

### Contributing Factors
1. **Cascading Failure**: Restarting kube-apiserver also stopped kube-controller-manager and kube-scheduler
2. **No Auto-Restart**: Control plane components didn't automatically restart after shutdown
3. **Manual Intervention Required**: Had to manually stop hung process and start all three components

### Unknown - Needs Investigation
**What triggered the restart?**
- Evidence shows `systemctl restart kube-apiserver.service` was executed
- Need to identify:
  - Who/what executed the restart command?
  - Was this automated or manual?
  - Was it part of a deployment or update?

---

## Impact Assessment

### Services Affected
- **All Kubernetes operations**: 3-minute outage
- **cloudflared**: Pod restarted during recovery
- **akash-services**: Pods temporarily unable to connect to API
- **monitoring**: Could not scrape metrics during outage
- **CI/CD**: Any pipeline operations failed

### Data Loss
- **None**: No data loss occurred
- etcd remained healthy throughout
- Pod state persisted

### User Impact
- **External services**: cloudflared tunnel briefly interrupted
- **Akash provider**: Temporary inability to lease GPUs
- **Monitoring dashboards**: 3-minute gap in metrics

---

## Resolution Steps

### Actions Taken
```bash
# 1. Force stop hung API server shutdown
ssh zephyr "sudo systemctl stop kube-apiserver.service"

# 2. Start API server
ssh zephyr "sudo systemctl start kube-apiserver.service"

# 3. Restart other control plane components
ssh zephyr "sudo systemctl start kube-controller-manager.service kube-scheduler.service"

# 4. Verify recovery
kubectl get nodes  # All nodes Ready
kubectl get pods -A  # All pods recovering
```

### Time to Recovery
- **Detection**: Immediate (kubectl failed)
- **Diagnosis**: ~2 minutes (systematic investigation)
- **Fix**: ~1 minute (3 service restarts)
- **Total Downtime**: ~3 minutes

---

## Prevention Measures

### Immediate Actions
1. **Identify Restart Trigger**
   - Check bash history: `cat ~/.bash_history | grep restart`
   - Check systemd journal: `journalctl -u kube-apiserver -S '1 hour ago'`
   - Check cron jobs and automation scripts
   - Review recent deployments/changes

2. **Add Monitoring**
   - Alert on control plane component failures
   - Monitor API server availability
   - Track systemd service restarts

3. **Document Restart Procedures**
   - When to restart control plane components
   - Proper restart sequence
   - Verification steps

### Long-Term Improvements
1. **Auto-Restart Configuration**
   - Configure systemd to auto-restart failed services
   - Add health check scripts
   - Implement automatic recovery

2. **High Availability Control Plane**
   - Deploy 3-master control plane (Planned for HA upgrade)
   - Eliminate single point of failure
   - Etcd clustering

3. **Change Management**
   - Require approval for control plane restarts
   - Document all maintenance windows
   - Implement change request process

---

## Lessons Learned

### What Went Well
1. **Systematic Debugging**: Followed debugging process to identify root cause
2. **Quick Recovery**: Full recovery in 3 minutes
3. **No Data Loss**: etcd remained healthy
4. **Controlled Fix**: No additional issues from restart

### What Needs Improvement
1. **Monitoring**: No alerting for control plane failures
2. **Auto-Recovery**: Components didn't restart automatically
3. **Change Tracking**: Don't know what triggered the restart
4. **Runbook**: No documented restart procedures

### Action Items
- [ ] Investigate what triggered the restart (HIGH PRIORITY)
- [ ] Add control plane monitoring alerts
- [ ] Configure systemd Restart=on-failure for control plane components
- [ ] Document control plane restart procedures
- [ ] Implement 3-master control plane (Planned for HA upgrade)

---

## Related Documents

- **HA Upgrade Plan**: `/etc/nixos/kubernetes-manifests/pod-disruption-budgets/IMPLEMENTATION-PLAN.md`
- **Baseline State**: `/etc/nixos/kubernetes-manifests/pod-disruption-budgets/BASELINE.md`
- **Rollback Procedures**: `/etc/nixos/kubernetes-manifests/ROLLBACK.md`

---

**Incident Status**: ✅ Resolved
**Follow-Up Required**: Yes (investigate restart trigger)
**Reviewed By**: Cluster Operations Team
**Last Updated**: 2026-03-22 07:59 UTC
