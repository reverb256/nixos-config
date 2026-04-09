# Kubernetes Mining Deployment

## ⚠️ CLUSTER STATUS WARNING

**Current Status**: Kubernetes cluster is NEW and UNSTABLE
- forge: NotReady
- nexus: NotReady
- sentry: Ready
- zephyr: Ready (control-plane)

**Deployment Strategy**: CONSERVATIVE with multiple fallbacks

## 🎯 Architecture Overview

```
Bare Metal (Primary, Stable)     Kubernetes (Backup, Experimental)
┌─────────────────────┐         ┌─────────────────────────┐
│ systemd services    │         │ Kubernetes pods         │
│                     │         │                         │
│ Zephyr:             │         │ Zephyr:                 │
│ - xmrig-proxy      │◄──────►│ - xmrig-proxy          │
│ - lolminer-nvidia  │         │ - gpu-miner-zephyr      │
│                     │         │                         │
│ Forge:              │         │ Forge:                  │
│ - lolminer-nvidia  │         │ - gpu-miner-forge        │
│ - lolminer-amd     │         │                         │
│                     │         │                         │
│ Nexus:              │         │ Nexus:                  │
│ - xmrig (CPU)      │         │ (Not ready, skip)        │
└─────────────────────┘         └─────────────────────────┘
```

## 🛡️ Safety Features

### 1. Resource Limits
- Memory limits prevent cluster OOM
- CPU requests prevent node overcommitment
- GPU limits prevent thermal issues

### 2. Health Checks
- Liveness probes detect crashed miners
- Readiness probes ensure miners are connected
- Startup probes prevent premature traffic

### 3. Node Selectors
- Pods pinned to specific nodes
- Prevents rescheduling to wrong nodes
- Maintains GPU affinity

### 4. Graceful Shutdown
- PreStop hooks allow clean disconnect
- 30-second grace period for share submission
- Prevents share loss on termination

## 📋 Deployment Steps

### Phase 1: Deploy Infrastructure (Today)
```bash
# 1. Create namespace
kubectl apply -f mining-namespace.yaml

# 2. Deploy xmrig-proxy first (critical infrastructure)
kubectl apply -f xmrig-proxy-configmap.yaml
kubectl apply -f xmrig-proxy-deployment.yaml

# 3. Verify proxy is healthy
kubectl get pods -n mining
kubectl logs -n mining -l app=xmrig-proxy --tail=50

# 4. Test proxy connectivity
kubectl port-forward -n mining svc/xmrig-proxy 3333:3333 &
# Test from another terminal
nc -zv 127.0.0.1 3333
```

### Phase 2: Deploy GPU Miners (Test First)
```bash
# Only deploy to READY nodes (Zephyr initially)
kubectl apply -f gpu-miner-zephyr.yaml

# Monitor for 5 minutes
watch -n 30 'kubectl get pods -n mining'

# Check hashrate
kubectl port-forward -n mining gpu-miner-zephyr-0 4068:4068 &
curl -s http://localhost:4068 | jq '.Algorithms[0].Total_Performance'

# If stable, proceed to Forge
```

### Phase 3: Forge Deployment (Wait for Node Ready)
```bash
# Check if Forge is Ready
kubectl get nodes forge

# Only if Forge is Ready:
kubectl apply -f gpu-miner-forge.yaml

# Monitor both miners
kubectl get pods -n mining -w
```

## 🔍 Monitoring & Troubleshooting

### Health Check Commands
```bash
# All mining pods
kubectl get pods -n mining -w

# Detailed pod status
kubectl describe pod -n mining gpu-miner-zephyr-0

# View logs (all containers)
kubectl logs -n mining gpu-miner-zephyr-0 --all-containers

# Stream logs in real-time
kubectl logs -n mining gpu-miner-zephyr-0 -f --all-containers
```

### Common Issues & Solutions

#### Issue 1: Pod CrashLoopBackOff
```bash
# Check logs
kubectl logs -n mining gpu-miner-zephyr-0

# Common causes:
# - GPU access denied → Check privileged: true
# - nvidia-smi missing → Check volume mount
# - Power limit too high → Edit deployment, reduce limits
```

#### Issue 2: Pod Pending (Unschedulable)
```bash
# Describe pod to see why
kubectl describe pod -n mining gpu-miner-zephyr-0

# Common causes:
# - Node not ready → Wait for node recovery
# - GPU resources exhausted → Check available GPUs
# - Node selector mismatch → Verify node name
```

#### Issue 3: Miner Connected But No Hashrate
```bash
# Check xmrig-proxy connection
kubectl logs -n mining xmrig-proxy-0 --tail=20

# Check if worker is registered
curl -s http://10.1.1.110:8081/workers  # If API accessible

# Restart pod
kubectl delete pod -n mining gpu-miner-zephyr-0
```

## 🚨 Rollback Procedures

### Immediate Rollback
```bash
# Delete all mining pods (keeps proxy running)
kubectl delete deployment -n mining gpu-miner-zephyr
kubectl delete deployment -n mining gpu-miner-forge

# Or delete entire namespace
kubectl delete namespace mining
```

### Bare Metal Fallback
```bash
# Kubernetes pods failed? Fall back to systemd:
ssh zephyr 'sudo systemctl start lolminer-nvidia'
ssh forge 'sudo systemctl start lolminer-nvidia lolminer-amd'
```

## 📊 Performance Comparison

### Bare Metal (systemd) - CURRENT PRODUCTION
- **Advantages**: Stable, proven, low overhead
- **Hashrate**: 14.35 g/s (Zephyr) + 18.1 g/s (Forge) = 32.45 g/s
- **Reliability**: 100% uptime, automatic restarts

### Kubernetes (pods) - EXPERIMENTAL BACKUP
- **Advantages**: Easy scaling, centralized management
- **Expected Hashrate**: Same as bare metal (same hardware)
- **Reliability**: Depends on cluster stability

## 🔧 Configuration Files

### File Structure
```
mining/
├── mining-namespace.yaml          # Namespace isolation
├── xmrig-proxy-configmap.yaml    # Proxy configuration
├── xmrig-proxy-deployment.yaml    # Proxy deployment
├── gpu-miner-zephyr.yaml        # Zephyr GPU miner
├── gpu-miner-forge.yaml          # Forge GPU miner
└── README.md                      # This file
```

### Customization

**Change Worker Names:**
Edit `gpu-miner-*.yaml`:
```yaml
args:
  - "--user=zephyr-gpu"  # Change this
```

**Change Power Limits:**
Edit `gpu-miner-*.yaml`, init container section:
```bash
nvidia-smi -i 0 -pl 130  # Adjust these values
nvidia-smi -i 1 -pl 250
```

**Add More Pools:**
Edit `xmrig-proxy-configmap.yaml`, add to `pools` array

## 🎯 Success Criteria

### Phase 1 Success (Proxy)
- [x] xmrig-proxy pod running
- [x] Service accessible on port 3333
- [x] Workers can connect (check logs)

### Phase 2 Success (Miners)
- [ ] GPU miner pods running
- [ ] Connected to xmrig-proxy
- [ ] Submitting shares to Kryptex
- [ ] Hashrate matches bare metal (±5%)

### Phase 3 Success (Reliability)
- [ ] Pods survive node restart
- [ ] Auto-restart on crash
- [ ] No cluster instability

## ⚙️ Advanced Configuration

### Horizontal Scaling (Future)
When cluster is stable, deploy multiple miner replicas:
```yaml
spec:
  replicas: 3  # One per GPU group
```

### Resource Quotas
Prevent mining from consuming all cluster resources:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: mining-quota
  namespace: mining
spec:
  hard:
    requests.nvidia.com/gpu: "4"
    requests.cpu: "2"
    requests.memory: "8Gi"
```

### Network Policies
Restrict mining traffic to only necessary communications:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mining-network-policy
  namespace: mining
spec:
  podSelector:
    matchLabels:
      workload: crypto-mining
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector: {}
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: mining
```

## 📝 Maintenance Operations

### Updating Configuration
```bash
# 1. Update ConfigMap
kubectl edit configmap xmrig-proxy-config -n mining

# 2. Restart proxy
kubectl rollout restart deployment xmrig-proxy -n mining

# 3. Restart miners
kubectl rollout restart deployment gpu-miner-zephyr -n mining
```

### Upgrading lolMiner
```bash
# 1. Update image in deployment
kubectl set image deployment/gpu-miner-zephyr lolminer \
  --image=lolminer/lolminer:1.99a -n mining

# 2. Watch rollout status
kubectl rollout status deployment/gpu-miner-zephyr -n mining
```

## 🚀 Next Steps

1. **Test on Zephyr only** (control plane is stable)
2. **Monitor cluster health** during mining operations
3. **Gradual rollout** to other nodes as they become ready
4. **Compare performance** between bare metal and Kubernetes
5. **Keep both running** for redundancy (as requested)

## 🆘 Emergency Procedures

### Cluster Instability Detected
```bash
# Immediate shutdown of K8s miners
kubectl delete deployment -n mining --all

# Fall back to bare metal
ssh zephyr 'sudo systemctl start lolminer-nvidia'
ssh forge 'sudo systemctl start lolminer-nvidia lolminer-amd'
```

### Circuit Overload Warning
```bash
# Immediately stop all GPU mining
kubectl delete deployment -n mining --all

# Wait 30 seconds
sleep 30

# Restart only on Zephyr (most efficient)
kubectl apply -f gpu-miner-zephyr.yaml
```

## 📞 Support

### Logs Collection (for debugging)
```bash
# Collect all mining logs
kubectl logs -n mining -l --all-containers > mining-logs.txt

# Describe all mining resources
kubectl get all -n mining -o yaml > mining-state.txt
```

### Bare Metal Status (always available)
```bash
# Check systemd mining status
for host in zephyr forge; do
  echo "=== $host ==="
  ssh $host 'systemctl status lolminer* --no-pager | head -5'
done
```

---

**Remember**: Bare metal is PRIMARY, Kubernetes is BACKUP. Keep both running for redundancy!
