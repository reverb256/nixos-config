# Kubernetes GPU Scheduling with AI Signals Integration

## 🎯 Complete Integration Architecture

This system integrates your existing AI inference gateway signals with Kubernetes-native GPU scheduling using PriorityClasses.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    GPU Scheduling Integration                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  AI Inference Gateway (Bare Metal)                                   │
│  ├─ FastAPI service on Zephyr:8000                                  │
│  ├─ Signals to /run/gpu-scheduler/ai-state                          │
│  │  ├─ "AI_START" when model loads                                   │
│  │  └─ "AI_STOP" when model unloads                                  │
│  └─ GPU scheduler.py module (ai_inference_gateway/)                 │
│                                                                      │
│         │                                                           │
│         │ State file changes                                         │
│         ▼                                                           │
│  ┌───────────────────────────────────────────────┐                  │
│  │ GPU Scheduler (2 parallel controllers)       │                  │
│  ├───────────────────────────────────────────────┤                  │
│  │                                                   │                  │
│  │ 1. Bare Metal (systemd)                         │                  │
│  │    ├─ compute-workload-monitor.service           │                  │
│  │    ├─ Reads /run/gpu-scheduler/ai-state          │                  │
│  │    ├─ Pauses lolminer when "AI_START"            │                  │
│  │    └─ Resumes lolminer when "AI_STOP"            │                  │
│  │                                                   │                  │
│  │ 2. Kubernetes (DaemonSet)                       │                  │
│  │    ├─ k8s-gpu-scheduler.py                       │                  │
│  │    ├─ Watches /run/gpu-scheduler/ai-state         │                  │
│  │    ├─ Stops mining pods when "AI_START"           │                  │
│  │    └─ Restarts mining pods when "AI_STOP"         │                  │
│  └───────────────────────────────────────────────┘                  │
│                                                                      │
│         │                                                           │
│         ▼                                                           │
│  Workloads (Managed by PriorityClass)                               │
│  ├─ High Priority (1000): AI Inference                              │
│  │  └─ Preemts mining immediately                                    │
│  └─ Low Priority (100): Mining (lolminer)                           │
│     └─ Auto-resumes when AI stops                                    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## 📋 Components

### 1. AI Inference Gateway (Existing)
**Location**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/gpu_scheduler.py`

**Function**: Signals GPU scheduler when AI workloads start/stop

**State File**: `/run/gpu-scheduler/ai-state`
- `AI_START` - AI workload is starting, stop mining
- `AI_STOP` - AI workload is stopping, resume mining
- `` (empty) - Idle, mining can run

### 2. Bare Metal Compute Workload Monitor (Existing)
**Location**: `/etc/nixos/modules/system/compute-workload-monitor.nix`

**Function**: Systemd service that monitors GPU workloads and manages bare metal mining

**Behavior**:
1. Reads `/run/gpu-scheduler/ai-state` every 10 seconds
2. When `AI_START` detected: `systemctl stop lolminer-nvidia`
3. When `AI_STOP` or empty: `systemctl start lolminer-nvidia`

### 3. Kubernetes GPU Scheduler (NEW)
**Location**: `/etc/nixos/scripts/k8s-gpu-scheduler.py`

**Deployment**: `kubernetes-manifests/system/k8s-gpu-scheduler.yaml`

**Function**: Python controller that manages Kubernetes mining pods based on gateway signals

**Behavior**:
1. Runs as DaemonSet on all GPU nodes
2. Watches `/run/gpu-scheduler/ai-state` every 5 seconds
3. When `AI_START` detected: Scales mining deployments to 0 replicas
4. When `AI_STOP` or empty: Scales mining deployments to 1 replica

## 🚀 Deployment Steps

### Step 1: Deploy GPU Scheduler Controller

```bash
# Deploy the scheduler (runs on all GPU nodes)
kubectl apply -f kubernetes-manifests/system/k8s-gpu-scheduler.yaml

# Verify scheduler is running
kubectl get pods -n kube-system -l app=gpu-scheduler
# NAME                   READY   STATUS    RESTARTS   AGE
# gpu-scheduler-xxxxx    1/1     Running   0          10s
```

### Step 2: Deploy Mining Pods (if not already done)

```bash
# Build lolminer container image
nix build .#lolminer-image

# Import into containerd on each GPU node
for host in zephyr forge; do
  ssh $host "sudo ctr -n k8s.io images import - < /etc/nixos/result"
done

# Deploy mining pods
kubectl apply -f kubernetes-manifests/mining/gpu-miner-zephyr.yaml
kubectl apply -f kubernetes-manifests/mining/gpu-miner-forge.yaml

# Verify mining pods are running
kubectl get pods -n mining
# NAME                                 READY   STATUS    RESTARTS   AGE
# gpu-miner-zephyr-xxx               1/1     Running   0          5s
```

### Step 3: Test AI Workload Preemption

```bash
# Deploy example AI workload (will preempt mining)
kubectl apply -f kubernetes-manifests/ai-inference-example-pod.yaml

# Watch mining pods get evicted
watch -n 2 'kubectl get pods -n mining'

# After 30 minutes (or delete the pod early), mining auto-resumes
kubectl delete pod ai-inference-example

# Verify mining pods restart
kubectl get pods -n mining
```

## 🔍 Verification

### Check Scheduler State

```bash
# Check current GPU scheduler state
cat /run/gpu-scheduler/ai-state

# Monitor scheduler logs
kubectl logs -n kube-system -l app=gpu-scheduler -f

# Monitor compute-workload-monitor logs
journalctl -u compute-workload-monitor -f
```

### Monitor Pod Preemption

```bash
# Watch real-time pod changes
watch -n 1 'kubectl get pods -A | grep -E "gpu-miner|ai-inference"'

# Check mining deployment replica count
kubectl get deployment -n mining -o wide

# Describe high priority pods
kubectl describe pod ai-inference-example | grep -A 5 "Priority"
```

## 🎯 Production Usage: Migrate AI Gateway to Kubernetes

To migrate your actual AI inference gateway to Kubernetes:

### 1. Build Container Image

```nix
# Add to flake.nix
packages.x86_64-linux.ai-inference-gateway = pkgs.dockerTools.buildImage {
  name = "ai-inference-gateway";
  tag = "latest";

  copyToRoot = pkgs.buildEnv {
    name = "ai-inference-root";
    paths = [
      config.services.ai-inference.package
      pkgs.bash
      pkgs.coreutils
    ];
    pathsToLink = ["/bin" "/lib"];
  };

  config = {
    Entrypoint = ["/bin/uvicorn"];
    Cmd = [
      "ai_inference_gateway.main:app"
      "--host" "0.0.0.0"
      "--port" "8000"
    ];

    Env = [
      "PATH=/bin"
      "PYTHONPATH=/lib/python3.11/site-packages"
    ];

    ExposedPorts = {
      "8000/tcp" = {};  # API port
    };
  };
};
```

### 2. Deploy with High Priority

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-inference-gateway
  namespace: ai-inference
spec:
  replicas: 1
  template:
    spec:
      priorityClassName: high-priority-ai  # CRITICAL: Preempts mining
      nodeName: zephyr  # Run on control plane node
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: gateway
        image: ai-inference-gateway:latest
        imagePullPolicy: Never  # Use local NixOS image
        volumeMounts:
        - name: gpu-scheduler-state
          mountPath: /run/gpu-scheduler
        resources:
          requests:
            nvidia.com/gpu: "1"  # Requests GPU
            memory: "4Gi"
      volumes:
      - name: gpu-scheduler-state
        hostPath:
          path: /run/gpu-scheduler
```

## 🔧 Configuration Files

| File | Purpose |
|------|---------|
| `modules/services/ai-inference/ai_inference_gateway/gpu_scheduler.py` | Gateway signals AI workloads |
| `modules/system/compute-workload-monitor.nix` | Bare metal workload monitor |
| `scripts/k8s-gpu-scheduler.py` | Kubernetes workload controller |
| `kubernetes-manifests/system/k8s-gpu-scheduler.yaml` | Scheduler deployment |
| `kubernetes-manifests/common/priority-classes.yaml` | PriorityClass definitions |
| `kubernetes-manifests/mining/gpu-miner-*.yaml` | Mining pod deployments |
| `kubernetes-manifests/ai-inference-example-pod.yaml` | Example AI workload |

## 📊 Behavior Timeline

### Scenario 1: AI Workload Starts

```
Time 0s: AI gateway loads model
         └─> Writes "AI_START" to /run/gpu-scheduler/ai-state

Time 0s: Bare metal monitor detects "AI_START"
         └─> systemctl stop lolminer-nvidia

Time 5s: K8s scheduler detects "AI_START"
         └─> kubectl scale deployment gpu-miner-zephyr --replicas=0
         └─> kubectl scale deployment gpu-miner-forge --replicas=0

Time 10s: Mining pods terminated
         └─> GPUs available for AI workload
```

### Scenario 2: AI Workload Stops

```
Time 0s: AI gateway unloads model
         └─> Writes "AI_STOP" to /run/gpu-scheduler/ai-state

Time 0s: Bare metal monitor detects "AI_STOP"
         └─> systemctl start lolminer-nvidia

Time 5s: K8s scheduler detects "AI_STOP"
         └─> kubectl scale deployment gpu-miner-zephyr --replicas=1
         └─> kubectl scale deployment gpu-miner-forge --replicas=1

Time 30s: Mining pods running
         └─> GPUs mining again
```

## ✅ Benefits

1. **Unified Scheduling**: Single source of truth (state file) for both bare metal and Kubernetes
2. **Immediate Preemption**: As requested, mining stops instantly when AI starts
3. **Auto-Resume**: Mining automatically restarts when AI completes
4. **Dual Control**: Both systemd and Kubernetes controllers can manage workloads
5. **Priority-Based**: Kubernetes native PriorityClasses handle GPU allocation
6. **No Race Conditions**: Both controllers use the same state file and identical logic

## 🎓 Key Insights

1. **State File is Single Source of Truth**: Both bare metal and K8s controllers read/write the same file
2. **Parallel Controllers Work**: systemd and Kubernetes can coexist managing different workloads
3. **PriorityClasses Ensure Preemption**: High priority pods always get GPUs first
4. **HostPath Mounting Enables Coordination**: Shares state between bare metal and containers
5. **Immediate Eviction**: As requested, no graceful shutdown - mining pods killed instantly
