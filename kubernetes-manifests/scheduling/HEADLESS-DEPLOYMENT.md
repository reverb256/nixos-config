# 🚀 COMPLETELY HEADLESS SCHEDULER MIGRATION
## Zero Web UI Required - 100% CLI Automation

**Version**: 2.0 (Headless)
**Status**: ✅ Ready for Production
**Web UI Required**: ❌ NO - Everything via CLI

---

## 🎯 Headless Migration Philosophy

This deployment requires **zero web UI interaction**. All monitoring, verification, and management is done through CLI tools.

### Why Headless?

✅ **Automation-friendly**: Can be scripted and automated
✅ **SSH-friendly**: Works over remote SSH sessions
✅ **CI/CD-ready**: Can be integrated into deployment pipelines
✅ **Faster**: No browser overhead
✅ **Audit trail**: All commands logged in shell history

---

## ⚡ Quick Start (5 Minutes)

### Deploy Everything

```bash
cd /etc/nixos/kubernetes-manifests/scheduling

# Complete headless deployment
./scripts/deploy-headless.sh
```

**That's it!** Everything is automated:
- ✅ Deploys YuniKorn scheduler
- ✅ Deploys Volcano scheduler
- ✅ Migrates all deployments
- ✅ Verifies installation (CLI-based)
- ✅ Tests preemption (automated)
- ✅ Sets up CLI monitoring tools

**Time**: ~2 minutes (automated)

---

## 📊 CLI Monitoring (No Web UI)

### Quick Status Check

```bash
# Quick status (one-liner)
./scripts/status-quick.sh
```

**Output**:
```
=== GPU Scheduler Status ===

📊 Scheduler Health:
  YuniKorn: 3 pods
  Volcano: 3 pods

🎮 Workloads:
  Mining pods: 2
  AI Gateway pods: 2

💾 State Management:
  Current state: IDLE
  Active workload: None
  Last updated: 2026-03-19T12:34:56Z

📋 Recent Scheduler Events:
  No recent events
```

### Live Monitoring

```bash
# Watch status in real-time (updates every 5 seconds)
./scripts/watch-status.sh
```

**Output** (auto-refreshing):
```
=== GPU Scheduler Live Status ===

📊 Schedulers:
  YuniKorn: 3 pods
  Volcano: 3 pods

🎮 GPU Workloads:
NAMESPACE   NAME                      STATUS    SCHEDULER   PRIORITY
mining      gpu-miner-zephyr-xxxxx   Running   yunikorn   low-priority-mining
mining      gpu-miner-forge-xxxxx    Running   yunikorn   low-priority-mining
ai-inference ai-inference-gateway-xxxx Running   yunikorn   high-priority-ai

💾 State:
State: IDLE | Workload: None | Updated: 2026-03-19T12:34:56Z

⏰ Last update: 2026-03-19 12:34:56
```

### Detailed Status

```bash
# Full monitoring (comprehensive)
./scripts/monitor.sh
```

---

## 🔍 Verification (CLI-Based)

### Check Scheduler Health

```bash
# YuniKorn scheduler health
kubectl get pods -n yunikorn -l app=yunikorn-scheduler

# Volcano scheduler health
kubectl get pods -n volcano-system -l app=volcano-scheduler

# Combined status
kubectl get pods -A -l 'app in (yunikorn-scheduler,volcano-scheduler)'
```

### Check State Management

```bash
# Current state
kubectl get configmap gpu-scheduler-state -n kube-system

# State details
kubectl describe configmap gpu-scheduler-state -n kube-system

# State JSON
kubectl get configmap gpu-scheduler-state -n kube-system -o json
```

### Check Deployments

```bash
# All GPU workload deployments
kubectl get deployment -A -o custom-columns=\
  NAMESPACE:.metadata.namespace,\
  NAME:.metadata.name,\
  REPLICAS:.spec.replicas,\
  AVAILABLE:.status.availableReplicas,\
  SCHEDULER:.spec.template.spec.schedulerName

# All GPU workload pods
kubectl get pods -A -l 'app in (gpu-miner,ai-inference-gateway)' \
  -o custom-columns=\
  NAMESPACE:.metadata.namespace,\
  NAME:.metadata.name,\
  STATUS:.status.phase,\
  SCHEDULER:.spec.template.spec.schedulerName,\
  PRIORITY:.spec.priorityClassName
```

### Check Priority Classes

```bash
# All priority classes
kubectl get priorityclasses

# Filtered view
kubectl get priorityclasses | grep -E "ai-inference|mining"
```

### Check PodGroups

```bash
# All PodGroups
kubectl get podgroup -A

# PodGroup details
kubectl describe podgroup gpu-miner-zephyr-group -n mining
```

---

## 🧪 Testing (CLI-Based)

### Test Preemption

```bash
# 1. Check current state
./scripts/status-quick.sh

# 2. Simulate AI workload starting
kubectl patch configmap gpu-scheduler-state -n kube-system \
  --type=merge \
  --patch='{"data":{"ai-state":"AI_START","active-workload":"test-inference"}}'

# 3. Watch preemption happen
kubectl get pods -n mining -w

# 4. Reset to idle
kubectl patch configmap gpu-scheduler-state -n kube-system \
  --type=merge \
  --patch='{"data":{"ai-state":"IDLE","active-workload":"none"}}'

# 5. Watch recovery
kubectl get pods -n mining -w
```

### Automated Preemption Test

```bash
# Built into deploy-headless.sh
# Re-run just the test phase:
cd /etc/nixos/kubernetes-manifests/scheduling
./scripts/deploy-headless.sh
# Phase 5 will test preemption automatically
```

---

## 📈 Monitoring Commands

### Real-Time Pod Watching

```bash
# Watch all GPU workload pods
kubectl get pods -A -l 'app in (gpu-miner,ai-inference-gateway)' -w

# Watch with custom columns
kubectl get pods -A -l 'app in (gpu-miner,ai-inference-gateway)' \
  -w \
  -o custom-columns=\
    NAMESPACE:.metadata.namespace,\
    NAME:.metadata.name,\
    STATUS:.status.phase,\
    RESTARTS:.status.restartCount,\
    AGE:.metadata.creationTimestamp
```

### Scheduler Logs

```bash
# YuniKorn scheduler logs (last 20 lines)
kubectl logs -n yunikorn deployment/yunikorn-scheduler --tail=20

# Volcano scheduler logs (last 20 lines)
kubectl logs -n volcano-system deployment/volcano-scheduler --tail=20

# Follow logs in real-time
kubectl logs -n yunikorn deployment/yunikorn-scheduler -f
```

### Events Monitoring

```bash
# All scheduler-related events
kubectl get events -A --field-selector involvedObject.kind=Pod -l 'app in (gpu-miner,ai-inference-gateway)'

# Recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Watch events in real-time
kubectl get events -A -w --field-selector involvedObject.kind=Pod
```

---

## 🔄 Rollback (CLI-Based)

### Complete Rollback

```bash
cd /etc/nixos/kubernetes-manifests/scheduling

# Rollback everything
./scripts/rollback.sh --all

# Re-enable custom scheduler
kubectl scale deployment gpu-scheduler -n kube-system --replicas=1

# Restore bare metal integration
git checkout modules/services/ai-inference/ai_inference_gateway/gpu_scheduler.py
just switch

# Verify rollback
./scripts/status-quick.sh
```

### Selective Rollback

```bash
# Rollback YuniKorn only
./scripts/rollback.sh --yunikorn

# Rollback Volcano only
./scripts/rollback.sh --volcano

# Rollback deployments only
./scripts/rollback.sh --revert-deployments
```

---

## 📋 Daily Operations (CLI-Based)

### Morning Status Check

```bash
# Quick status
./scripts/status-quick.sh

# Detailed status if issues
./scripts/monitor.sh
```

### Monitor During AI Workloads

```bash
# Watch pods during AI inference
kubectl get pods -A -l app=ai-inference-gateway -w

# Check scheduler state
kubectl get configmap gpu-scheduler-state -n kube-system -o yaml

# Check YuniKorn decisions
kubectl logs -n yunikorn deployment/yunikorn-scheduler --tail=50 | grep -i "preempt\|schedule"
```

### Troubleshooting Issues

```bash
# Check if pods are pending
kubectl get pods -A | grep Pending

# Describe pending pod to see why
kubectl describe pod <pod-name> -n <namespace>

# Check scheduler logs
kubectl logs -n yunikorn deployment/yunikorn-scheduler --tail=100 | grep -i error
kubectl logs -n volcano-system deployment/volcano-scheduler --tail=100 | grep -i error

# Check recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -50
```

---

## 🎯 Key Commands Reference

### Status Commands

| Command | Purpose |
|---------|---------|
| `./scripts/status-quick.sh` | Quick status overview |
| `./scripts/watch-status.sh` | Live monitoring (5s refresh) |
| `./scripts/monitor.sh` | Detailed monitoring |
| `kubectl get pods -A -w` | Watch all pods |
| `kubectl logs -n yunikorn deployment/yunikorn-scheduler -f` | Follow YuniKorn logs |

### State Management

| Command | Purpose |
|---------|---------|
| `kubectl get configmap gpu-scheduler-state -n kube-system` | Check current state |
| `kubectl patch configmap ... --patch='{"data":{"ai-state":"AI_START"}}'` | Signal AI starting |
| `kubectl patch configmap ... --patch='{"data":{"ai-state":"IDLE"}}'` | Signal AI idle |

### Verification

| Command | Purpose |
|---------|---------|
| `kubectl get pods -n yunikorn` | Check YuniKorn health |
| `kubectl get pods -n volcano-system` | Check Volcano health |
| `kubectl get podgroup -A` | Check gang scheduling |
| `kubectl get priorityclasses` | Check priority classes |

---

## 🚨 Troubleshooting (CLI-Only)

### Issue: Can't see scheduler decisions

**Solution**: Check logs instead of web UI
```bash
# YuniKorn scheduling decisions
kubectl logs -n yunikorn deployment/yunikorn-scheduler -f | grep -i "schedule\|preempt"

# Volcano scheduling decisions
kubectl logs -n volcano-system deployment/volcano-scheduler -f | grep -i "schedule\|gang"
```

### Issue: Preemption not working

**Solution**: Verify via CLI
```bash
# Check priority classes
kubectl get pod <mining-pod> -n mining -o jsonpath='{.spec.priorityClassName}'

# Check ConfigMap state
kubectl get configmap gpu-scheduler-state -n kube-system -o yaml

# Check scheduler preemption config
kubectl get configmap yunikorn-config -n yunikorn -o yaml | grep -i preempt
```

### Issue: Pods stuck in Pending

**Solution**: Describe pod via CLI
```bash
# See why pod is pending
kubectl describe pod <pod-name> -n <namespace>

# Check scheduler logs
kubectl logs -n yunikorn deployment/yunikorn-scheduler | tail -100

# Check events
kubectl get events -n <namespace> | tail -20
```

---

## ✅ Post-Deployment Checklist (CLI-Only)

### Immediately After Deployment

- [ ] Run `./scripts/status-quick.sh` - all systems healthy
- [ ] Run `kubectl get pods -A -w` - pods starting correctly
- [ ] Run `kubectl get configmap gpu-scheduler-state -n kube-system` - state accessible
- [ ] Test preemption: patch ConfigMap to AI_START, watch mining pods

### Day 1 Monitoring

- [ ] Check status: `./scripts/status-quick.sh`
- [ ] Review logs: `kubectl logs -n yunikorn deployment/yunikorn-scheduler --tail=100`
- [ ] Verify preemption worked during AI workload
- [ ] Check no pods in Pending state

### Week 1 Validation

- [ ] Daily status checks via CLI
- [ ] Monitor scheduler logs for errors
- [ ] Verify GPU utilization improved
- [ ] Validate preemption behavior under load

---

## 🎓 Key Insights

`★ Insight ─────────────────────────────────────`
**Headless Architecture Benefits**
- **CLI-first design**: All operations via kubectl and bash
- **Scriptable**: Can be automated in CI/CD pipelines
- **SSH-friendly**: Works over remote connections
- **Audit trail**: All commands in shell history
- **Faster**: No browser overhead, instant feedback
`─────────────────────────────────────────────────`

### What You DON'T Need

❌ Web browser
❌ Port forwarding to localhost
❌ Dashboard UI
❌ Grafana (optional, not required)
❌ Kubectl plugins (standard kubectl only)

### What You DO Need

✅ kubectl (standard)
✅ helm (for installation only)
✅ bash scripts (provided)
✅ SSH access (optional)

---

## 📚 Command Reference Card

### Essential Commands

```bash
# Quick status
./scripts/status-quick.sh

# Live monitoring
./scripts/watch-status.sh

# Watch pods
kubectl get pods -A -w

# Check logs
kubectl logs -n yunikorn deployment/yunikorn-scheduler --tail=20

# Test preemption
kubectl patch configmap gpu-scheduler-state -n kube-system \
  --type=merge --patch='{"data":{"ai-state":"AI_START"}}'

# Reset state
kubectl patch configmap gpu-scheduler-state -n kube-system \
  --type=merge --patch='{"data":{"ai-state":"IDLE"}}'

# Rollback
./scripts/rollback.sh --all
```

---

**Version**: 2.0 (Headless)
**Status**: ✅ Production Ready
**Web UI Required**: ❌ NO - 100% CLI-based

**Deploy Now**: `./scripts/deploy-headless.sh`
**Monitor Now**: `./scripts/watch-status.sh`
