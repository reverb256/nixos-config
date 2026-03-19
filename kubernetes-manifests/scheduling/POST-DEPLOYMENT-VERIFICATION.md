# 📊 POST-DEPLOYMENT VERIFICATION
## Comprehensive Health Check After Migration

---

## ✅ Immediate Verification (First 5 Minutes)

### 1. Scheduler Health ✅
```bash
# YuniKorn scheduler health
kubectl get pods -n yunikorn -l app=yunikorn-scheduler

# Expected: 2-3 pods Running
kubectl rollout status deployment -n yunikorn yunikorn-scheduler

# Volcano scheduler health
kubectl get pods -n volcano-system -l app=volcano-scheduler

# Expected: 2-3 pods Running
kubectl rollout status deployment -n volcano-system volcano-scheduler
```

**Success Criteria**: All scheduler pods Running

---

### 2. Workload Deployment ✅
```bash
# Mining deployments
kubectl get deployment -n mining
kubectl get pods -n mining -l app=gpu-miner

# AI Gateway deployment
kubectl get deployment -n ai-inference
kubectl get pods -n ai-inference -l app=ai-inference-gateway

# Check rollout status
kubectl rollout status deployment -n mining gpu-miner-zephyr
kubectl rollout status deployment -n ai-inference ai-inference-gateway
```

**Success Criteria**: All deployments rolled out successfully

---

### 3. Security Policies ✅
```bash
# ServiceAccounts
kubectl get sa -n mining gpu-miner-sa
kubectl get sa -n ai-inference ai-gateway-sa

# NetworkPolicies
kubectl get networkpolicy -n mining
kubectl get networkpolicy -n ai-inference

# Pod Security Standards
kubectl get namespace mining -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
kubectl get namespace ai-inference -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
```

**Success Criteria**: All security resources present

---

## 🔍 Functional Testing (10 Minutes)

### 4. Scheduler State Management ✅
```bash
# Check current state
kubectl get configmap gpu-scheduler-state -n kube-system -o yaml

# Expected: ai-state: IDLE

# Test state update
kubectl patch configmap gpu-scheduler-state -n kube-system \
  --type=merge \
  --patch='{"data":{"ai-state":"TEST_STATE"}}'

# Verify update
kubectl get configmap gpu-scheduler-state -n kube-system -o jsonpath='{.data.ai-state}'

# Reset to IDLE
kubectl patch configmap gpu-scheduler-state -n kube-system \
  --type=merge \
  --patch='{"data":{"ai-state":"IDLE"}}'
```

**Success Criteria**: State updates work correctly

---

### 5. Preemption Test ✅
```bash
# Set AI_START state
kubectl patch configmap gpu-scheduler-state -n kube-system \
  --type=merge \
  --patch='{"data":{"ai-state":"AI_START","active-workload":"test-inference"}}'

# Watch mining pods (should be affected)
kubectl get pods -n mining -w &
WATCH_PID=$!

# Wait 10 seconds
sleep 10

# Check mining pods
kubectl get pods -n mining -l app=gpu-miner

# Reset to IDLE
kubectl patch configmap gpu-scheduler-state -n kube-system \
  --type=merge \
  --patch='{"data":{"ai-state":"IDLE","active-workload":"none"}}'

# Stop watching
kill $WATCH_PID 2>/dev/null || true

# Wait for recovery
sleep 10

# Verify mining pods recovered
kubectl get pods -n mining -l app=gpu-miner
```

**Success Criteria**: Mining pods recover after state reset

---

### 6. Network Connectivity ✅
```bash
# Test AI Gateway connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n ai-inference -- \
  curl -s http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/health

# Test DNS resolution
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n mining -- \
  nslookup kubernetes.default

# Test external connectivity (if applicable)
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n mining -- \
  curl -I https://www.google.com
```

**Success Criteria**: All connectivity tests pass

---

## 📈 Performance Verification (15 Minutes)

### 7. GPU Utilization ✅
```bash
# Check GPU allocation
kubectl describe nodes | grep -A 5 "Allocated resources"

# Verify GPU requests/limits
kubectl get pods -n mining -o jsonpath='{.items[*].spec.containers[*].resources.requests.nvidia\.com/gpu}'
kubectl get pods -n ai-inference -o jsonpath='{.items[*].spec.containers[*].resources.requests.nvidia\.com/gpu}'

# Use nvidia-smi on nodes
ssh zephyr "nvidia-smi"
```

**Success Criteria**: GPUs are allocated and utilized

---

### 8. Pod Resource Usage ✅
```bash
# Check resource usage
kubectl top pods -n mining
kubectl top pods -n ai-inference

# Verify resource limits are respected
kubectl describe pod -n mining <pod-name> | grep -A 5 Limits
```

**Success Criteria**: Pods within resource limits

---

### 9. Scheduler Logs ✅
```bash
# YuniKorn scheduler logs
kubectl logs -n yunikorn deployment/yunikorn-scheduler --tail=50 | grep -i "error\|preempt"

# Volcano scheduler logs
kubectl logs -n volcano-system deployment/volcano-scheduler --tail=50 | grep -i "error\|schedule"

# Check for any scheduling failures
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

**Success Criteria**: No errors in scheduler logs

---

## 🔒 Security Verification (5 Minutes)

### 10. RBAC Effectiveness ✅
```bash
# Test bare metal kubectl access (from zephyr/forge)
# This should work with the ClusterRoleBinding
kubectl auth can-i update configmap/gpu-scheduler-state -n kube-system --as=kubernetes-admin

# Test ServiceAccount permissions
kubectl auth can-i get configmap --as=system:serviceaccount:kube-system:gpu-scheduler-client -n kube-system
```

**Success Criteria**: RBAC permissions work as expected

---

### 11. Network Policy Effectiveness ✅
```bash
# From a pod in mining, test connectivity to AI (should be blocked)
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n mining -- \
  curl -s http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/health

# Expected: Connection timeout (NetworkPolicy blocking)

# From a pod in ai-inference, test connectivity to backend (should work)
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n ai-inference -- \
  curl -s http://qdrant.qdrant.svc.cluster.local:6333/health
```

**Success Criteria**: NetworkPolicies are blocking/allowing correctly

---

## 📊 Monitoring Verification (5 Minutes)

### 12. Metrics Collection ✅
```bash
# Check if ServiceMonitors are working
kubectl get servicemonitor -n monitoring

# Verify Prometheus targets
kubectl get prometheus -n monitoring prometheus-k8s -o jsonpath='{.spec}' | grep -i gpu

# Check metrics endpoint
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n mining -- \
  curl -s http://gpu-miner-zephyr:4068/
```

**Success Criteria**: Metrics are being collected

---

### 13. Alerting Rules ✅
```bash
# Check PrometheusRules
kubectl get prometheusrule -n monitoring gpu-scheduler-alerts

# Verify alert rules are loaded
kubectl exec -n monitoring prometheus-k8s-0 -- \
  amtool rule list | grep gpu-scheduler
```

**Success Criteria**: Alert rules are loaded

---

## ✅ Final Health Check (5 Minutes)

### 14. Comprehensive Status ✅
```bash
# Run the quick status script
./scripts/status-quick.sh

# Expected output:
# ✓ YuniKorn: 3 pods
# ✓ Volcano: 3 pods
# ✓ Mining: 2 pods
# ✓ AI Gateway: 2 pods
# ✓ State: IDLE
```

**Success Criteria**: All components healthy

---

### 15. Deployment Summary ✅
```bash
# Generate deployment summary
echo "=== GPU Scheduler Deployment Summary ==="
echo ""
echo "Schedulers:"
kubectl get pods -n yunikorn -l app=yunikorn-scheduler --no-headers | wc -l
kubectl get pods -n volcano-system -l app=volcano-scheduler --no-headers | wc -l
echo ""
echo "Workloads:"
kubectl get pods -n mining -l app=gpu-miner --no-headers | wc -l
kubectl get pods -n ai-inference -l app=ai-inference-gateway --no-headers | wc -l
echo ""
echo "Security:"
kubectl get networkpolicy -A --no-headers | wc -l
kubectl get serviceaccount -A --no-headers | grep -E "gpu-miner|ai-gateway" | wc -l
echo ""
echo "Operational:"
kubectl get pdb -A --no-headers | wc -l
kubectl get resourcequota -A --no-headers | wc -l
```

**Success Criteria**: All resources deployed correctly

---

## 🚨 Troubleshooting Common Issues

### Issue: Pods stuck in Pending
```bash
# Describe the pod to see why
kubectl describe pod <pod-name> -n <namespace>

# Check scheduler logs
kubectl logs -n yunikorn deployment/yunikorn-scheduler | tail -100
kubectl logs -n volcano-system deployment/volcano-scheduler | tail -100

# Check events
kubectl get events -n <namespace> | tail -20
```

### Issue: Preemption not working
```bash
# Check priority classes
kubectl get pods -n mining -o jsonpath='{.items[*].spec.priorityClassName}'

# Check ConfigMap state
kubectl get configmap gpu-scheduler-state -n kube-system -o yaml

# Check scheduler preemption config
kubectl get configmap yunikorn-config -n yunikorn -o yaml | grep -i preempt
```

### Issue: NetworkPolicy blocking traffic
```bash
# Check which policies apply to a pod
kubectl get networkpolicy -n <namespace> -o yaml

# Test connectivity from pod
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n <namespace> -- \
  curl -v <target-url>
```

### Issue: RBAC permission denied
```bash
# Check effective permissions
kubectl auth can-i --list --as=system:serviceaccount:<namespace>:<sa-name>

# Describe the role/rolebinding
kubectl describe role -n <namespace> <role-name>
kubectl describe rolebinding -n <namespace> <binding-name>
```

---

## ✅ Sign-Off

**Post-Deployment Verification Completed By**: ___________
**Date**: ___________
**Time**: ___________

### Verification Results:
☐ All scheduler pods Running
☐ All workload deployments rolled out
☐ Security policies applied
☐ Preemption test passed
☐ Network connectivity verified
☐ GPU utilization confirmed
☐ Scheduler logs clean
☐ RBAC working correctly
☐ NetworkPolicies effective
☐ Metrics being collected
☐ Alerting rules loaded
☐ Final health check passed

### Overall Status:
☐ **PASSED** - All verifications successful, ready for production
☐ **FAILED** - Issues detected, see troubleshooting section

### Issues Found:
1. ___________
2. ___________
3. ___________

### Resolution Plan:
1. ___________
2. ___________
3. ___________

---

**Document Version**: 1.0
**Last Updated**: 2026-03-19
