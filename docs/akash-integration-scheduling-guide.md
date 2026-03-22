# Akash Network Integration - Scheduling & Resource Distribution Guide

**Provider:** reverb256.ca | **Last Updated:** 2026-03-22

> **IMPORTANT:** This guide covers the intelligent scheduling architecture during the HA rebuild transition. GPU resource allocation is managed by a unified auction engine that coordinates between mining, Kubernetes, Akash, and gaming workloads.

---

## 🏗️ Architecture Overview

### GPU Resource Allocation Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                  GPU Resource Marketplace                     │
│            (Unified Auction Engine for 5 GPUs)                │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌──────────────────┼──────────────────┬──────────────────┐
        │                  │                  │                  │
        ▼                  ▼                  ▼                  ▼
    ┌─────────┐       ┌──────────┐      ┌──────────┐      ┌──────────┐
    │ Mining  │       │K8s Work- │      │  Akash   │      │ Gaming   │
    │ Bidder  │       │loads     │      │ Network  │      │ Override │
    │         │       │          │      │ Leases   │      │          │
    └────┬────┘       └─────┬────┘      └────┬─────┘      └────┬─────┘
         │                  │                   │                   │
         ▼                  ▼                   ▼                   ▼
    ┌─────────────────────────────────────────────────────────────────────┐
    │                    YuniKorn Scheduler                        │
    │           (Priority-based Preemption + Queue Management)       │
    └─────────────────────────────────────────────────────────────────────┘
                            │
         ┌──────────────────┼──────────────────┬──────────────────┐
         ▼                  ▼                  ▼                  ▼
    ┌─────────┐       ┌──────────┐      ┌──────────┐      ┌──────────┐
    │ GPU Pod │       │GPU Pod   │      │GPU Pod   │      │GPU Pod   │
    │(Mining) │       │(K8s)     │      │(Akash)   │      │(Gaming)  │
    │         │       │          │      │          │      │          │
    └─────────┘       └──────────┘      └──────────┘      └──────────┘
```

---

## 🎯 Priority Classes (Preemption Order)

| Priority Class | Value | Usage | Can Be Preempted By | Typical Workloads |
|----------------|--------|-------|---------------------|-----------------|
| **production-workload-critical** | 900,000,000 | Critical infrastructure | None (only system-cluster-critical) | Gaming, Akash provider, infrastructure |
| **production-workload-high** | 800,000,000 | Important services | Gaming only | Databases, web services, Akash leases |
| **production-workload-medium** | 700,000,000 | Standard production | Gaming, production-high | Background workers, batch jobs |
| **development-workload** | 500,000,000 | Development/Testing | Gaming, production-* | Dev environments, experiments |
| **batch-workload** | 400,000,000 | Scheduled tasks | Gaming, production-* | CronJobs, periodic tasks |
| **best-effort-workload** | 200,000,000 | Default (preemptible) | All higher priorities | Mining, demos, monitoring |

**Default:** `best-effort-workload` (200M) - All pods without explicit priority class

---

## 💰 GPU Bidding Economics

### Revenue per GPU (USD/hour)

| Bidder | Base Rate | Actual Revenue | Priority | Preemption Behavior |
|--------|----------|---------------|----------|---------------------|
| **Gaming** | $0.00 | $0.00 | 900M | Preempts everything (priority override) |
| **Akash** | Market rate × 90% | $0.05-$0.50 | 800M | Preempts mining, dev, batch |
| **Kubernetes** | $2.50 | $2.50 | 800M | Preempts mining, dev, batch |
| **Mining** | $0.014 | $0.014 | 200M | Preempted by everyone |

### Auction Logic

**Every 30 seconds**, the marketplace runs an auction:

```bash
Mining Bid:     $0.014/GPU/hr × 5 GPUs = $0.07/hr
Kubernetes Bid: $2.50/GPU/hr × active pods
Akash Bid:      Σ(active_lease_prices) × 0.90 (profit margin)
Gaming:        $0 (but wins by priority override)

Winner gets GPU allocation for next 30-second interval
```

**Key Insight:** Akash leases only win if they generate more revenue than Kubernetes workloads.

---

## 🔄 Akash Deployment Lifecycle

### 1. Lease Creation

```yaml
# Tenant creates deployment via Console/CLI
→ Provider validates resources
→ Bid placed on marketplace
→ Auction runs (30s intervals)
→ If won: Lease created, Kubernetes pod scheduled
```

### 2. GPU Allocation

```yaml
# Akash lease arrives
→ YuniKorn scheduler evaluates priority
→ Checks GPU availability (nvidia.com/gpu)
→ Creates pod with priorityClassName: production-workload-high
→ Pod scheduled to appropriate node
→ Mining preempted (if needed) to free GPU
```

### 3. Runtime Behavior

```yaml
During lease:
  → Gaming detected → Gaming placeholder scaled up (replicas: 0→2)
  → YuniKorn preempts lower priority pods (including Akash!)
  → Akash lease paused/interrupted
  → Gaming ends → Placeholder scaled down
  → Akash lease resumes (if still active)
```

### 4. Lease Termination

```yaml
Lease ends:
  → Pod deleted
  → GPU resources freed
  → Next auction (30s later) may reallocate to mining/K8s
```

---

## 📝 Required Adaptations for Akash Deployments

### 1. Priority Class Assignment

**CRITICAL:** All Akash deployments MUST use explicit priority classes:

```yaml
---
version: "2.0"

services:
  app:
    image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
    expose:
      - port: 8080
        as: 80
        to:
          - global: true

profiles:
  compute:
    app:
      resources:
        cpu:
          units: 4
        memory:
          size: 8Gi
        gpu:
          units: 1
          attributes:
            vendor:
              nvidia:
                - model: rtx3090
        storage:
          - size: 50Gi
            attributes:
              persistent: true
              class: beta2

placement:
  reverb256:
    signedBy:
      - akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
    pricing:
      app:
        denom: uakt
        amount: 20000

deployment:
  app:
    reverb256:
      profile: app
      count: 1
      # CRITICAL: Set priority class for preemption behavior
      priorityClassName: production-workload-high  # or -medium
```

**Priority Recommendations:**

| Use Case | Recommended Priority | Rationale |
|----------|-------------------|------------|
| **Short-term inference (<4 hrs)** | production-workload-high | Less likely to be preempted by gaming |
| **Long-running training** | production-workload-medium | Gaming can preempt if needed |
| **Batch/Background jobs** | batch-workload | Explicitly marked as batch |
| **Development/Testing** | development-workload | Preemptible by production workloads |
| **Always-on services** | production-workload-high | Higher priority for availability |

### 2. Resource Limits

```yaml
profiles:
  compute:
    app:
      resources:
        cpu:
          units: 4
        memory:
          size: 8Gi
        gpu:
          units: 1
          attributes:
            vendor:
              nvidia:
                - model: rtx3090
                # CRITICAL: Always specify model
        storage:
          - size: 50Gi
            attributes:
              persistent: true
              class: beta2
```

**CRITICAL Rules:**
- ✅ ALWAYS specify GPU model (vendor.nvidia.model)
- ✅ NEVER use `:latest` image tags
- ✅ Use explicit resource limits
- ✅ Specify storage class (beta2/beta3/ram)

### 3. Storage Configuration

```yaml
storage:
  # Model weights (persistent)
  - size: 50Gi
    attributes:
      persistent: true
      class: beta2  # Standard persistent storage

  # Checkpoints (persistent)
  - size: 10Gi
    attributes:
      persistent: true
      class: beta2

  # Dataset cache (can be non-persistent if cached from external)
  - size: 100Gi
    attributes:
      persistent: false
      class: ram  # Fast but volatile (pod restart = data loss)
```

### 4. Health Checks

```yaml
services:
  app:
    image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
    expose:
      - port: 8080
        as: 80
        to:
          - global: true
    params:
      health:
        port: 8080
        path: /health
        interval: 30s
        timeout: 10s
```

---

## ⚠️ Resource Quotas & Constraints

### Namespace Quotas

```yaml
# mining namespace (example)
ResourceQuota:
  hard:
    requests.nvidia.com/gpu: 5  # Total GPUs in cluster
    requests.cpu: "40"
    requests.memory: 80Gi
  scopes:
    - priorityClass: gaming-high
```

**Impact:** Akash leases compete for same GPU pool within quota.

### Node Constraints

| Node | GPUs | Constraints | Typical Akash Allocation |
|------|------|------------|------------------------|
| **zephyr** | 2 (RTX 3090 + 3060 Ti) | Control-plane + AI workstation | 1 GPU max (leave 1 for local use) |
| **nexus** | 1 (RTX 3060 Ti) | Storage worker | 1 GPU full allocation |
| **forge** | 2 (RTX 4060) | Mining + AI | Both GPUs (multi-GPU workloads) |
| **sentry** | 0 (AMD only) | Monitoring | NO GPU (NVIDIA only) |

**Key Constraint:** NO AMD GPU support for Akash on this provider.

### Pod Density Limits

```
Max pods per node: 110 (Kubernetes default)
Current usage across cluster: ~30-40 pods
Risk: Pod IP exhaustion if >88 pods/node
Mitigation: Akash deployments limited by ResourceQuota
```

---

## 🎯 Deployment Best Practices

### 1. Right-Size Resources

| Workload Type | CPU | Memory | GPU | Example |
|---------------|-----|--------|-----|---------|
| **Inference (7B model)** | 2-4 units | 8-16Gi | 1× RTX 3060 Ti | Llama-7B |
| **Inference (70B model)** | 4-8 units | 16-32Gi | 1× RTX 3090 | Llama-70B |
| **Training (small)** | 4-8 units | 16-32Gi | 2× RTX 4060 | Fine-tuning |
| **Data processing** | 2-4 units | 4-8Gi | None | ETL pipelines |

### 2. Fault Tolerance

```yaml
# Use restart policies for resilience
services:
  training-job:
    image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
    restart_policy:
      # On failure (but not completion)
      condition: "on-failure"
      max_retries: 3
```

### 3. Cost Optimization

| Strategy | When to Use | Savings |
|----------|-------------|---------|
| **Use RTX 3060 Ti** | Small models, inference | 25% cheaper than RTX 3090 |
| **Shorter leases** | Batch jobs, testing | Pay only for usage time |
| **Spot pricing** | Non-urgent workloads | Dynamic pricing based on cluster demand |

---

## 🔍 Monitoring & Debugging

### Check Lease Status

```bash
# List active Akash leases
kubectl get leases -n akash-services

# Get lease details
kubectl get lease <lease-name> -n akash-services -o yaml

# Check provider status
kubectl get pods -n akash-services -l app=akash-provider
```

### GPU Allocation

```bash
# Check GPU usage
kubectl describe nodes | grep nvidia.com/gpu

# View Akash pod resource requests
kubectl get pods -n akash-services -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.requests}{"\n"}{end}'

# Check marketplace auction results
curl http://localhost:9200/metrics | grep auction_winner
```

### Preemption Events

```bash
# View YuniKorn preemption events
kubectl get events -n akash-services --field-selector reason=Preempting

# Check gaming state
kubectl get configmap -n kube-system gpu-scheduler-state -o yaml
```

---

## 🚨 Common Issues & Solutions

### Issue 1: "Insufficient nvidia.com/gpu"

**Cause:** All GPUs allocated to higher priority workloads

**Solution:**
1. Check gaming status (gaming placeholder pods)
2. Wait for current leases to complete
3. Use higher priority class if urgent
4. Consider deploying during off-peak hours

### Issue 2: "Pod stuck in Pending state"

**Cause:** Node selector incompatible or resource limits

**Solution:**
1. Verify node selector matches available GPUs
2. Check `kubectl describe pod <pod-name>` for events
3. Ensure GPU model matches node labels
4. Try removing strict node selector

### Issue 3: Lease interrupted during gaming

**Cause:** Gaming priority preemption

**Solution:**
1. **Expected behavior** - Gaming has highest priority
2. Lease will resume after gaming ends (if within lease term)
3. Use `production-workload-critical` if gaming interruption is unacceptable (but this will block gaming)

### Issue 4: Deployment exceeds namespace quota

**Cause:** ResourceQuota limits hit

**Solution:**
1. Check current quota: `kubectl get resourcequota -n akash-services`
2. Wait for other leases to complete
3. Contact provider to increase quotas

---

## 📊 Integration with Existing Infrastructure

### Current State (HA Rebuild in Progress)

| Component | Status | Notes |
|-----------|--------|-------|
| **YuniKorn Scheduler** | ✅ Active | Primary scheduler for GPU workloads |
| **Volcano Scheduler** | ⚠️ Migration complete | Legacy batch scheduler, now using YuniKorn |
| **GPU Marketplace** | ✅ Active | Unified auction engine operational |
| **Compute-Market** | ✅ Active | Bidding system integrated with YuniKorn |
| **Gaming Detection** | ✅ Active | GameMode + placeholder pattern |
| **Cloudflare Integration** | ✅ Active | Automated DNS, cache, monitoring |
| **Akash Provider** | ✅ Active | Mainnet, 5 GPUs advertised |

### How Akash Leases Flow

```
1. Tenant submits SDL via Console
   ↓
2. Akash provider validates resources
   ↓
3. Compute-market receives bid request
   ↓
4. Auction runs (every 30s)
   ↓
5. If won: Lease manifests as Kubernetes Pod
   ↓
6. YuniKorn schedules pod with priorityClassName
   ↓
7. Pod allocates GPU (nvidia.com/gpu resource)
   ↓
8. Deployment accessible via ingress
   ↓
9. Gaming can preempt (if priority allows)
   ↓
10. Lease ends → GPU freed → Next auction
```

---

## 🎓 Key Takeaways

### For Tenants

1. **Set appropriate priority class** based on workload criticality
2. **Expect preemptions** from gaming (highest priority)
3. **Use exact GPU models** from provider attributes
4. **Monitor lease status** via provider dashboard
5. **Design for interruption** - use checkpoints for long-running jobs

### For Provider Operations

1. **Monitor auction results** via compute-market metrics
2. **Track GPU utilization** across all bidders
3. **Balance revenue** - Akash ($0.05-$0.50/GPU/hr) vs K8s ($2.50/GPU/hr) vs mining ($0.014/GPU/hr)
4. **Gaming preemption** is automatic via GameMode + YuniKorn
5. **Priority classes** control preemption behavior

### Adaptations Needed

1. ✅ **Priority class** in every deployment manifest
2. ✅ **GPU model specification** (no generic "any GPU" requests)
3. ✅ **Resource limits** to prevent overallocation
4. ✅ **Health checks** for liveness/readiness
5. ⚠️ **Storage** - Only local path provisioner (data lost on pod termination)

---

**Version:** 1.0
**Last Updated:** 2026-03-22
**Next Review:** After HA rebuild completion
