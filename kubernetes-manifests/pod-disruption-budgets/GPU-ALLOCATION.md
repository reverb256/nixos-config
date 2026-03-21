# GPU Allocation Strategy - Preemptible Mining Architecture

## Cluster GPU Inventory

| Node | GPUs | Models | Akash? | Mining Priority | Higher Priority Workloads |
|------|------|--------|--------|-----------------|--------------------------|
| **Zephyr** | 2 | RTX 3090, RTX 3060 Ti (8GB) | ✅ Yes | Preemptible | **Gaming (3090)**, Akash (both), AI inference |
| **Nexus** | 1 | RTX 3060 Ti (8GB) | ✅ Yes | Preemptible | Akash (highest priority), storage |
| **Sentry** | 1 | RX 5600 XT (AMD) | ❌ No | Preemptible | AI inference (llamafile), monitoring |
| **Forge** | 4 | 2x RTX 4060, 2x RX 5700 XT | 2x NVIDIA | Preemptible | Akash (NVIDIA only), GPU compute |

**Total GPUs**: 8 (5 NVIDIA + 3 AMD)
**Akash GPUs**: 5 NVIDIA (3090, 3060Ti-zephyr, 3060Ti-nexus, 4060-forge-0, 4060-forge-1)
**AMD GPUs**: 3 (not available for Akash - 5700 XT x2, 5600 XT)
**Mining Strategy**: **ALL GPUs preemptible** - mine when idle, yield to higher priority workloads
**Priority Hierarchy**: Gaming (3090) > Akash (5 NVIDIA) > AI Inference (5600 XT) > Mining

## Preemption Hierarchy

### Priority Levels (Highest to Lowest)

| Priority | Workload | Preemption Action | Examples |
|----------|----------|-------------------|----------|
| **P0 - Critical** | Akash GPU jobs | Evict all miners immediately | Container inference, training |
| **P1 - User** | Gaming | Evict miners on gaming GPU | Zephyr 3060 Ti (compute-workload-monitor) |
| **P2 - Production** | AI inference | Evict miners if needed | llamafile on Sentry |
| **P3 - Background** | Mining | Always preemptible | lolminer on all GPUs |

**Key Principle**: Mining runs **only when GPUs would otherwise be idle**. Never blocks higher priority workloads.

## GPU Scheduling Strategy

### Default State: Mining (All GPUs Idle)
```
Zephyr: 3090 mining, 3060 Ti mining
Nexus: 3060 Ti mining
Sentry: 5600 XT mining (AMD)
Forge: 4060 #1 mining, 4060 #2 mining, 5700 XT #1 mining (AMD), 5700 XT #2 mining (AMD)
Total: 8/8 GPUs mining (5 NVIDIA + 3 AMD)
```

### Akash Job Arrives (P0 - Critical)
```yaml
# Akash deployment requests 2x NVIDIA GPUs (AMD not supported)
apiVersion: batch/v1
kind: Job
metadata:
  name: akash-gpu-job
spec:
  template:
    spec:
      priorityClassName: critical-production  # Higher than mining
      nodeSelector:
        gpu.vendor: nvidia  # Only NVIDIA GPUs
      containers:
      - resources:
          requests:
            nvidia.com/gpu: 2
```
**Action**: Yunikorn scheduler preempts 2 NVIDIA mining pods, Akash claims GPUs
```
Zephyr: 3090 AKASH JOB, 3060 Ti mining
Nexus: 3060 Ti AKASH JOB
Sentry: 5600 XT mining (AMD - not available for Akash)
Forge: 4060 #1 mining, 4060 #2 mining, 5700 XT #1 mining (AMD), 5700 XT #2 mining (AMD)
Total: 6/8 GPUs mining, 2/5 NVIDIA GPUs Akash
```

### Gaming Starts on Zephyr (P1 - User)
**Action**: compute-workload-monitor detects gaming, preempts Zephyr 3090 miner/akash
```
Zephyr: 3090 GAMING, 3060 Ti mining
Nexus: 3060 Ti AKASH JOB
Sentry: 5600 XT mining (AMD)
Forge: 4060 #1 mining, 4060 #2 mining, 5700 XT #1 mining (AMD), 5700 XT #2 mining (AMD)
Total: 6/8 GPUs mining, 1/8 GPU gaming, 1/5 NVIDIA GPUs Akash
```

### AI Inference Starts on Sentry (P2 - Production)
**Action**: llamafile startup preempts Sentry 5600 XT AMD miner
```
Zephyr: 3090 GAMING, 3060 Ti mining
Nexus: 3060 Ti AKASH JOB
Sentry: 5600 XT AI INFERENCE (AMD ROCm/Vulkan)
Forge: 4060 #1 mining, 4060 #2 mining, 5700 XT #1 mining (AMD), 5700 XT #2 mining (AMD)
Total: 5/8 GPUs mining (2 NVIDIA + 3 AMD), 1/8 GPU gaming, 1/5 NVIDIA GPU Akash, 1/3 AMD GPU AI
```

### AI Workload on Forge AMD GPUs (P2 - Production)
**Action**: AI training/inference job submitted to Forge 5700 XT GPUs
```
Zephyr: 3090 mining, 3060 Ti mining
Nexus: 3060 Ti mining
Sentry: 5600 XT mining (AMD)
Forge: 4060 #1 mining, 4060 #2 mining, 5700 XT #1 AI WORKLOAD, 5700 XT #2 AI WORKLOAD
Total: 6/8 GPUs mining (2 NVIDIA + 1 AMD), 2/3 AMD GPUs for AI
```

## PriorityClass Configuration

```yaml
# critical-production (Priority 1000000)
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: critical-production
value: 1000000
globalDefault: false
description: "Akash GPU jobs, revenue-generating workloads"

# user-interactive (Priority 750000)
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: user-interactive
value: 750000
globalDefault: false
description: "Gaming, user-initiated workloads"

# production-services (Priority 500000)
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-services
value: 500000
globalDefault: false
description: "AI inference, monitoring, cluster services"

# background-mining (Priority 10000)
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: background-mining
value: 10000
globalDefault: false
description: "Preemptible mining - always yields to higher priority"
```

## Mining Deployment Configuration

### Preemptible Mining Pods

```yaml
# gpu-miner-preemptible.yaml (template for all GPUs)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-miner-zephyr-3090
  namespace: mining
spec:
  replicas: 1
  strategy:
    type: Recreate  # Only 1 pod per GPU
  selector:
    matchLabels:
      app: gpu-miner
      node: zephyr
      gpu-id: "0"
  template:
    spec:
      priorityClassName: background-mining  # LOWEST PRIORITY
      nodeName: zephyr
      schedulerName: yunikorn  # Use Yunikorn for GPU-aware scheduling
      containers:
      - name: lolminer
        image: docker.io/swamp7/lolminer:latest
        resources:
          requests:
            nvidia.com/gpu: 1
            cpu: "1000m"
            memory: "2000Mi"
          limits:
            nvidia.com/gpu: 1
            cpu: "2000m"
            memory: "4000Mi"
        env:
        - name: GPU_DEVICE
          value: "0"
        - name: WALLET
          value: "krxXVNVMM7.zephyr-3090"
```

### Akash GPU Job Example

```yaml
# akash-gpu-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: akash-inference-job
  namespace: akash-cpu-test
spec:
  backoffLimit: 3
  template:
    metadata:
      labels:
        app: akash-gpu
    spec:
      priorityClassName: critical-production  # HIGHEST PRIORITY
      schedulerName: yunikorn
      restartPolicy: OnFailure
      containers:
      - name: inference
        image: tensorflow/tensorflow:latest-gpu
        resources:
          requests:
            nvidia.com/gpu: 1
            cpu: "2000m"
            memory: "8000Mi"
          limits:
            nvidia.com/gpu: 1
            cpu: "4000m"
            memory: "16000Mi"
        command: ["python", "inference_script.py"]
```

## Preemption Flow

### Akash Job Preempts Mining

1. **Akash client submits GPU job**
   ```yaml
   apiVersion: akash.network/v1
   kind: Provider
   metadata:
     name: akash-provider
   spec:
     gpuResources:
       - nvidia.com/gpu: 2
   ```

2. **Yunikorn scheduler evaluates request**
   - Checks available GPU capacity
   - Finds 8 GPUs running mining pods (priority 10000)
   - Akash job priority = 1000000 (higher)

3. **Preemption decision**
   ```
   Available GPUs: 0
   Mining pods: 8 (priority 10000)
   Akash request: 2 GPUs (priority 1000000)
   Decision: Preempt 2 mining pods
   ```

4. **Preemption execution**
   ```bash
   # Yunikorn evicts 2 lowest-priority mining pods
   kubectl delete pod gpu-miner-forge-nvidia-0 -n mining
   kubectl delete pod gpu-miner-forge-nvidia-1 -n mining
   ```

5. **Akash job scheduled**
   ```
   Akash job claims Forge 4060 #1 and 4060 #2
   Mining pods automatically rescheduled on available GPUs
   ```

### Gaming Preempts Mining (Zephyr)

1. **User launches game**
   - Steam/Lutris starts game process
   - compute-workload-monitor detects via process name

2. **Gaming detection**
   ```bash
   # compute-workload-monitor.nix
   systemd.services.compute-workload-monitor = {
     script = ''
       # Detect gaming process
       if pgrep -f "Steam|lutris|wine" > /dev/null; then
         # Preempt Zephyr 3060 Ti miner
         kubectl scale deployment gpu-miner-zephyr-3060ti --replicas=0
       fi
     '';
   };
   ```

3. **Mining paused**
   ```
   Zephyr 3060 Ti: Mining → Gaming (instant transition)
   GPU freed for gaming within 1-2 seconds
   ```

4. **Game exits → mining resumes**
   ```bash
   kubectl scale deployment gpu-miner-zephyr-3060ti --replicas=1
   ```

## Resource Quotas with Preemption

### Namespace Quotas

```yaml
# mining-namespace-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gpu-mining-quota
  namespace: mining
spec:
  hard:
    requests.nvidia.com/gpu: "8"    # Can request all GPUs
    requests.amd.com/gpu: "3"       # Can request all AMD GPUs
    requests.cpu: "8000m"
    requests.memory: "16000Mi"
  scopes:
  - PriorityClass
  matcher:
    labelSelector:
      matchLabels:
        priorityClass: background-mining
```

```yaml
# akash-namespace-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: akash-gpu-quota
  namespace: akash-cpu-test
spec:
  hard:
    requests.nvidia.com/gpu: "8"    # Can preempt all mining
    requests.cpu: "16000m"
    requests.memory: "32000Mi"
  scopes:
  - PriorityClass
  matcher:
    labelSelector:
      matchLabels:
        priorityClass: critical-production
```

## Monitoring and Observability

### Preemption Metrics

```yaml
# Preemption monitoring dashboard
- Preemption rate (mining pods evicted/hour)
- GPU utilization by priority level
- Akash job queue depth
- Mining revenue impact (lost hashrate)
- Gaming session detection
```

### Alerts

```yaml
# alerts.yaml
- alert: HighPreemptionRate
  expr: rate(kube_pod_status_terminated_reason{reason="Evicted"}[1h]) > 10
  annotations:
    summary: "High mining preemption rate - check Akash job volume"

- alert: MiningRevenueDrop
  expr: mining_hashrate < expected_hashrate * 0.5
  annotations:
    summary: "Mining hashrate dropped 50% - high GPU utilization by other workloads"
```

## Deployment Strategy

### Phase 1: Enable PriorityClasses (Week 1)
```bash
kubectl apply -f priorityclasses.yaml
```

### Phase 2: Update Mining Deployments (Week 1)
```bash
# Add priorityClassName: background-mining to all mining pods
kubectl set deployment gpu-miner-zephyr-3090 \
  --overrides='{"spec":{"template":{"spec":{"priorityClassName":"background-mining"}}}}'
```

### Phase 3: Configure Yunikorn for GPU Scheduling (Week 2)
```bash
# Enable Yunikorn scheduler
kubectl apply -f yunikorn-config.yaml
```

### Phase 4: Test Preemption (Week 2)
```bash
# Submit test Akash job
kubectl apply -f test-akash-job.yaml

# Verify mining pods evicted
kubectl get pods -n mining -w

# Verify Akash job scheduled
kubectl get pods -n akash-cpu-test
```

### Phase 5: Deploy Gaming Detection (Week 3)
```bash
# Enable compute-workload-monitor on Zephyr
just switch  # Applies to local host
```

## Benefits of Preemptible Mining

### Economic Benefits
1. **Maximize GPU utilization**: Mine 24/7 when GPUs idle
2. **Never block revenue**: Akash jobs always have priority
3. **Dynamic optimization**: Automatically adapt to workload changes
4. **Reduce idle time**: Zero GPU idle time unless all higher priority workloads active

### Operational Benefits
1. **Simplified planning**: No dedicated mining GPUs to manage
2. **Automatic scaling**: Mining auto-scales based on demand
3. **Graceful degradation**: Mining pauses, no service disruption
4. **Transparent to users**: Gaming/Akash performance unaffected

### Technical Benefits
1. **Priority-based scheduling**: Clear hierarchy of workloads
2. **Fine-grained control**: Per-pod priority configuration
3. **Observability**: Track preemption events and GPU allocation
4. **Flexibility**: Easy to add new priority levels or workloads

## Constraints and Policies

### Hard Constraints
- **Akash jobs ALWAYS preempt mining** (P0 vs P3)
- **Gaming ALWAYS preempts mining on Zephyr 3060 Ti** (user experience)
- **AI inference preempts mining on Sentry** (production service)
- **Mining never preempts anything** (lowest priority)

### Soft Constraints
- Prefer preempting Forge miners first (4 GPUs, dedicated worker)
- Then preempt Zephyr/Nexus miners (gaming/AI priority nodes)
- Keep Sentry miner running last (only 1 GPU, monitoring priority)
- Minimize preemption frequency (batch Akash jobs when possible)

## Future Enhancements

### GPU Sharing (TimeSlicing)
- Allow multiple low-priority workloads per GPU
- Mining + Akash dev jobs on same GPU
- Requires GPU partitioning (MPS for NVIDIA, MIG for newer GPUs)

### Predictive Scheduling
- ML model predicts gaming/Akash usage patterns
- Preempt mining proactively before high-priority jobs arrive
- Reduce preemption latency

### Dynamic Voltage/Frequency Scaling
- Underclock GPUs during mining (reduce power, improve efficiency)
- Overclock GPUs during Akash jobs (maximize performance)
- Automatic tuning based on workload type

---

**Version**: 2.0
**Created**: 2026-03-21
**Updated**: 2026-03-21 (Preemptible architecture)
**Maintainer**: Cluster Operations Team

## Deployment Configuration

### Zephyr Mining
```yaml
# gpu-miner-zephyr-3090.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-miner-zephyr-3090
  namespace: mining
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gpu-miner-zephyr
      gpu-id: "0"  # RTX 3090
  template:
    spec:
      nodeName: zephyr
      containers:
      - name: lolminer
        resources:
          limits:
            nvidia.com/gpu: 1
```

### Nexus Mining
```yaml
# gpu-miner-nexus-3060ti.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-miner-nexus-3060ti
  namespace: mining
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gpu-miner-nexus
      gpu-id: "0"  # RTX 3060 Ti
  template:
    spec:
      nodeName: nexus
      containers:
      - name: lolminer
        resources:
          limits:
            nvidia.com/gpu: 1
```

### Forge Mining (4 GPUs)
```yaml
# gpu-miner-forge-nvidia-0.yaml (RTX 4060 #1)
# gpu-miner-forge-nvidia-1.yaml (RTX 4060 #2)
# gpu-miner-forge-amd-0.yaml (RX 5700 XT #1)
# gpu-miner-forge-amd-1.yaml (RX 5700 XT #2)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-miner-forge-nvidia-0
  namespace: mining
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gpu-miner-forge
      gpu-id: "0"
      gpu-type: nvidia
  template:
    spec:
      nodeName: forge
      containers:
      - name: lolminer
        resources:
          limits:
            nvidia.com/gpu: 1
```

## GPU Resource Management

### Zephyr Gaming Integration
- **compute-workload-monitor** service pauses mining during gaming
- Monitors: GPU utilization, process names (gaming processes)
- Action: `kubectl scale deployment gpu-miner-zephyr-3090 --replicas=0`
- Resume: Scale back to 1 when gaming stops

### Sentry AI Inference
- **llamafile** service uses RX 5600 XT for LLM inference
- Backend: ROCm or Vulkan (configurable)
- No mining conflicts - miner scaled to 0
- Priority: AI inference > mining

### Forge Dedicated Mining
- All 4 GPUs dedicated to mining
- No gaming, no AI inference
- Maximum uptime for revenue generation
- Node selector: `gpu-role: mining`

## Resource Requests

| Node | GPU Miners | CPU Requests | RAM Requests | GPU Type |
|------|------------|--------------|--------------|----------|
| Zephyr | 1 (3090) | 1000m | 2000 Mi | NVIDIA |
| Nexus | 1 (3060 Ti) | 1000m | 2000 Mi | NVIDIA |
| Sentry | 0 | 0 | 0 | N/A (AI only) |
| Forge | 4 (2x NVIDIA + 2x AMD) | 4000m | 8000 Mi | Mixed |

**Total Mining Resources**:
- CPU: 6000m (6 cores)
- RAM: 12000 Mi (12 GB)
- GPUs: 6 (4 NVIDIA + 2 AMD)

## Monitoring

### GPU Utilization
```bash
# Check GPU usage across cluster
kubectl get pods -n mining -o wide
ssh zephyr "nvidia-smi"
ssh nexus "nvidia-smi"
ssh forge "nvidia-smi && rocm-smi"
```

### Mining Revenue Tracking
- Hashrate aggregation via xmrig-proxy on Zephyr (10.1.1.110:3333)
- Wallet-based tracking per GPU
- Revenue per GPU monitoring

### Conflicts Detection
```bash
# Check for GPU conflicts
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.nodeName == "zephyr") | select(.spec.containers[].resources.limits."nvidia.com/gpu" == "1") | {name: .metadata.name, namespace: .metadata.namespace}'
```

## Rollout Procedures

### Gaming Mode (Zephyr)
1. User launches game (detected by compute-workload-monitor)
2. Mining automatically paused: `kubectl scale deployment gpu-miner-zephyr-3090 --replicas=0`
3. GPU freed for gaming
4. Game exits
5. Mining resumed: `kubectl scale deployment gpu-miner-zephyr-3090 --replicas=1`

### AI Inference Mode (Sentry)
1. llamafile service starts
2. RX 5600 XT reserved for AI
3. No mining conflicts (already scaled to 0)
4. GPU dedicated to LLM inference

### Maintenance Mode
1. Node drain: `kubectl drain forge --ignore-daemonsets --delete-emptydir-data`
2. Miners automatically evicted (respect PDBs)
3. Maintenance completed
4. Node uncordon: `kubectl uncordon forge`
5. Miners automatically rescheduled

## Constraints and Policies

### Hard Constraints
- **NEVER** mine on Zephyr 3060 Ti (gaming GPU)
- **NEVER** mine on Sentry 5600 XT (AI inference GPU)
- **ALWAYS** pause Zephyr 3090 mining during gaming
- **ALWAYS** keep Forge miners running (dedicated node)

### Soft Constraints
- Prefer NVIDIA miners on Zephyr/Nexus (better hashrate)
- Use AMD miners on Forge (fill GPU capacity)
- Monitor GPU temperatures (auto-throttle at 80°C)
- Power limit GPUs (140W AMD, 250W NVIDIA)

## Future Considerations

### GPU Expansion
- Add 2nd GPU to Nexus (currently has 1)
- Upgrade Sentry 5600 XT to higher-end AMD GPU
- Consider dedicated AI inference node (separate from Sentry)

### Mining Optimization
- Auto-switch algorithms based on profitability
- Dynamic power limits based on electricity cost
- Pool failover configuration
- Hashrate monitoring and alerting

### AI/ML Integration
- Zephyr 3060 Ti for ML training (PyTorch, TensorFlow)
- Sentry 5600 XT for LLM inference (llamafile)
- Potential GPU sharing (TimeSlicing, MPS) for multiple workloads

---

**Version**: 1.0
**Created**: 2026-03-21
**Maintainer**: Cluster Operations Team
