# Quick Start: Kubernetes GPU Scheduling with AI Signals

## 🚀 One-Command Deployment

```bash
# Deploy everything
kubectl apply -f kubernetes-manifests/common/priority-classes.yaml && \
kubectl apply -f kubernetes-manifests/system/k8s-gpu-scheduler.yaml && \
echo "✅ GPU Scheduler deployed!"
```

## 📋 Verification Commands

```bash
# Check scheduler is running
kubectl get pods -n kube-system -l app=gpu-scheduler

# Check priority classes
kubectl get priorityclasses

# Check current state
cat /run/gpu-scheduler/ai-state

# Watch scheduler logs
kubectl logs -n kube-system -l app=gpu-scheduler -f
```

## 🧪 Test Preemption

```bash
# Terminal 1: Watch mining pods
watch -n 1 'kubectl get pods -n mining'

# Terminal 2: Deploy AI workload (will preempt mining)
kubectl apply -f kubernetes-manifests/ai-inference-example-pod.yaml

# Terminal 3: Watch scheduler logs
kubectl logs -n kube-system -l app=gpu-scheduler -f

# After 30 min (or anytime): Delete AI pod to resume mining
kubectl delete pod ai-inference-example
```

## 🎯 What Happens

### When AI Starts
1. AI pod writes `AI_START` to `/run/gpu-scheduler/ai-state`
2. Kubernetes scheduler detects state change (5s)
3. Scales mining deployments to 0 replicas
4. **Mining pods evicted immediately** ✅
5. AI pod gets GPUs

### When AI Stops
1. AI pod writes `AI_STOP` to `/run/gpu-scheduler/ai-state`
2. Kubernetes scheduler detects state change (5s)
3. Scales mining deployments to 1 replica
4. **Mining pods auto-resume** ✅
5. GPUs return to mining

## 🔧 Integration Points

| System | State File | Action on AI_START | Action on AI_STOP |
|--------|-----------|-------------------|-------------------|
| AI Gateway | Writes to | Signals workload start | Signals workload stop |
| Bare Metal Monitor | Reads from | Stops lolminer-nvidia | Starts lolminer-nvidia |
| K8s Scheduler | Reads from | Scales mining→0 | Scales mining→1 |

## 📚 Full Documentation

- `/etc/nixos/docs/kubernetes-ai-signals-integration.md` - Complete integration guide
- `/etc/nixos/docs/kubernetes-gpu-scheduling.md` - Architecture overview
- `/etc/nixos/kubernetes-manifests/ai-inference-example-pod.yaml` - Example AI workload
