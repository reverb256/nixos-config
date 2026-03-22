# Akash Deployment Spec Sheet - reverb256.ca Provider

**Provider:** reverb256.ca
**Region:** us-west
**Zone:** homelab
**Provider Address:** akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
**Last Updated:** 2026-03-22

---

## 📋 Provider Quick Reference

### Available Resources

| Resource Type | Total Available | Per-Node Limits |
|---------------|-----------------|-----------------|
| **CPU Cores** | 78 cores | 12-30 cores/node |
| **Memory** | 123GB RAM | 11-64GB/node |
| **GPUs** | 5 NVIDIA GPUs | 1-2 GPUs/node |
| **Storage** | 8.4TB raw | Local path provisioner |

### GPU Inventory

| GPU Model | Count | VRAM | Best For | Price (uakt/block) |
|-----------|-------|------|----------|---------------------|
| **RTX 3090** | 1 | 24GB | Large models, high-VRAM workloads | 20,000 (~$0.20/hr) |
| **RTX 4060** | 2 | 8GB each | Mid-range GPU computing | 18,000 (~$0.18/hr) |
| **RTX 3060 Ti** | 2 | 8GB each | Budget-friendly GPU tasks | 15,000 (~$0.15/hr) |

### Storage Classes

| Storage Class | Type | Persistent | Use Case |
|---------------|------|------------|----------|
| **beta2** | Local SSD | ✅ Yes | Standard workloads, databases |
| **beta3** | Local SSD | ✅ Yes | Enhanced performance |
| **ram** | RAM disk | ❌ No | Temporary data, caching (fastest) |

### Network Access

| Feature | Value |
|---------|-------|
| **Ingress Pattern** | `*.ingress.reverb256.ca` |
| **Dedicated DNS** | `*.dedicated.ingress.reverb256.ca` |
| **Region** | us-west |
| **Latency Tier** | Low (West Coast North America) |

---

## 📝 SDL Template - GPU Workload

### Example 1: Single GPU Deployment (RTX 3090)

```yaml
---
version: "2.0"

services:
  # AI/ML Inference Service
  inference:
    image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
    command: ["python", "-u", "app.py"]
    expose:
      - port: 8080
        as: 80
        to:
          - global: true
        accept:
          - hello.ingress.reverb256.ca
    env:
      - MODEL_PATH=/models/model.pt
      - BATCH_SIZE=32

profiles:
  compute:
    inference:
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
      pricing:
        inference:
          denom: uakt
          amount: 20000

deployment:
  inference:
    reverb256:
      profile: inference
      count: 1
```

**Expected Cost:** ~$0.20/hr × 24 hrs = **$4.80/day**

---

### Example 2: Multi-GPU Deployment (2× RTX 4060)

```yaml
---
version: "2.0"

services:
  # Distributed Training Job
  trainer:
    image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
    command: ["python", "train.py --distributed"]
    expose:
      - port: 6006
        as: 6006
        to:
          - global: true
        accept:
          - training.dedicated.ingress.reverb256.ca
    env:
      - WORLD_SIZE=2
      - MASTER_ADDR=trainer-0
    params:
      storage:
        data:
          mount: /data
          readOnly: false

profiles:
  compute:
    trainer:
      resources:
        cpu:
          units: 8
        memory:
          size: 16Gi
        gpu:
          units: 2
          attributes:
            vendor:
              nvidia:
                - model: rtx4060
        storage:
          - size: 200Gi
            attributes:
              persistent: true
              class: beta3
          - size: 100Gi
            attributes:
              persistent: true
              class: beta2

  placement:
    reverb256:
      pricing:
        trainer:
          denom: uakt
          amount: 36000  # 18,000 × 2 GPUs

deployment:
  trainer:
    reverb256:
      profile: trainer
      count: 1
```

**Expected Cost:** ~$0.36/hr × 24 hrs = **$8.64/day**

---

### Example 3: Budget GPU Workload (RTX 3060 Ti)

```yaml
---
version: "2.0"

services:
  # Web Service with GPU
  api:
    image: node:20-alpine
    command: ["node", "server.js"]
    expose:
      - port: 3000
        as: 80
        to:
          - global: true
        accept:
          - api.ingress.reverb256.ca

profiles:
  compute:
    api:
      resources:
        cpu:
          units: 2
        memory:
          size: 4Gi
        gpu:
          units: 1
          attributes:
            vendor:
              nvidia:
                - model: rtx3060ti
        storage:
          - size: 10Gi
            attributes:
              persistent: true
              class: beta2

  placement:
    reverb256:
      signedBy:
        - akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
      pricing:
        api:
          denom: uakt
          amount: 15000

deployment:
  api:
    reverb256:
      profile: api
      count: 1
```

**Expected Cost:** ~$0.15/hr × 24 hrs = **$3.60/day**

---

## 🎯 Deployment Specifications

### GPU Selection Guide

| Use Case | Recommended GPU | Reasoning |
|----------|-----------------|-----------|
| **Large LLMs (70B+ params)** | RTX 3090 (24GB) | Fits larger models in single GPU |
| **Multi-GPU Training** | 2× RTX 4060 (16GB total) | Good balance of VRAM + cost |
| **Inference/Serving** | RTX 3060 Ti | Lowest cost, sufficient for most models |
| **Computer Vision** | RTX 4060 | Ada Lovelace architecture, good throughput |
| **3D Rendering** | RTX 3090 | Large VRAM for complex scenes |

### Resource Requirements by Workload Type

| Workload | CPU | Memory | GPU | Storage |
|----------|-----|--------|-----|---------|
| **LLM Inference (7B-13B)** | 2-4 cores | 8-16Gi | 1× RTX 3060 Ti | 10-50Gi |
| **LLM Inference (30B-70B)** | 4-8 cores | 16-32Gi | 1× RTX 3090 | 50-100Gi |
| **Training (Small Models)** | 4-8 cores | 16-32Gi | 2× RTX 4060 | 100-200Gi |
| **Data Processing** | 2-4 cores | 4-8Gi | None | 20-100Gi |
| **Web Service + GPU** | 2-4 cores | 4-8Gi | 1× RTX 3060 Ti | 10-20Gi |

### Storage Recommendations

| Data Type | Recommended Class | Size | Persistent |
|-----------|-------------------|------|------------|
| **Models/Weights** | beta2 | 10-100Gi | ✅ Yes |
| **Training Data** | beta3 | 100-500Gi | ✅ Yes |
| **Checkpoints** | beta2 | 20-50Gi | ✅ Yes |
| **Temporary/Cache** | ram | 1-10Gi | ❌ No |
| **Databases** | beta2 | 20-100Gi | ✅ Yes |

---

## 🔧 Deployment Configuration

### Required Attributes

For successful deployment on this provider, **always include these attributes**:

```yaml
profiles:
  compute:
    your-service:
      resources:
        cpu:
          units: <units>
        memory:
          size: <size>
        gpu:
          units: <count>
          attributes:
            vendor:
              nvidia:
                - model: <rtx3090|rtx4060|rtx3060ti>
```

### Regional Attributes

```yaml
placement:
  reverb256:
    region: us-west
    zone: homelab
    signedBy:
      - akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

### Storage Attributes

```yaml
storage:
  - size: <size>
    attributes:
      persistent: true
      class: beta2  # or beta3, ram
```

---

## 💰 Pricing Guide

### GPU Pricing Breakdown

| GPU | uakt/block | USD/hr | USD/day | USD/month (30 days) |
|-----|-----------|--------|---------|---------------------|
| RTX 3090 | 20,000 | $0.20 | $4.80 | $144.00 |
| RTX 4060 | 18,000 | $0.18 | $4.32 | $129.60 |
| RTX 3060 Ti | 15,000 | $0.15 | $3.60 | $108.00 |

### Base Pricing (per 1000 units)

| Resource | uakt/block | Notes |
|----------|-----------|-------|
| CPU | 1.5 | ~$0.000015/hr per 1000 units |
| Memory | 0.8 | ~$0.000008/hr per 1000 units |
| Storage | 0.02 | ~$0.0000002/hr per 1000 units |

### Cost Optimization Tips

1. **Use Right-Sized Resources** - Don't overallocate CPU/memory
2. **Choose Appropriate GPU** - Use RTX 3060 Ti for workloads that don't need 24GB VRAM
3. **Storage Efficiency** - Use beta2 for most cases, beta3 only if you need the performance
4. **Short-Term Deployments** - Deploy only when needed, tear down when idle

---

## 🌐 Accessing Your Deployment

### Ingress URL Patterns

Once deployed, your service will be accessible at:

```
https://<lease-id>.inggress.reverb256.ca
```

For dedicated DNS (if configured):
```
https://<lease-id>.dedicated.ingress.reverb256.ca
```

### Finding Your Lease ID

```bash
# Using Akash CLI
provider-services query lease <dseq> --gseq <gseq> --oseq <oseq> \
  --node https://rpc.akashnet.net:443 \
  --provider akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

### Health Check

```bash
# Check service status
curl https://<lease-id>.ingress.reverb256.ca/health

# Check logs
kubectl logs -n akash-services -l app.akash.deploymentID=<lease-id>
```

---

## ⚠️ Important Notes

### Resource Constraints

1. **GPU Availability** - Only 5 GPUs total. High demand may lead to wait times.
2. **Storage** - All storage is local to nodes. Data is lost when deployment ends.
3. **No Floating IPs** - Use ingress patterns for external access.

### Best Practices

1. **Always Use Explicit Image Tags** - Never use `:latest`
2. **Include Health Checks** - Define `/health` or `/ready` endpoints
3. **Use Persistent Storage** - Only if you need data persistence across restarts
4. **Monitor Resource Usage** - Don't overallocate; you pay for what you reserve
5. **Set Resource Limits** - Prevent runaway resource consumption

### Unsupported Features

- ❌ AMD GPUs (only NVIDIA supported on this provider)
- ❌ Host Network (use ClusterIP + ingress)
- ❌ LoadBalancer services (use ingress instead)
- ❌ StatefulSets with persistent data across deployments

---

## 📞 Provider Support

### Provider Status

- **Status Page:** https://status.provider.reverb256.ca
- **Provider Bid Engine:** https://provider.reverb256.ca
- **Documentation:** /etc/nixos/docs/akash-provider-capabilities.md

### Getting Help

1. Check provider status page for outages
2. Review Akash Network docs: https://akash.network/docs
3. Check awesome-akash for SDL templates: https://github.com/akash-network/awesome-akash

---

**Version:** 1.0
**Last Updated:** 2026-03-22
**Provider:** reverb256.ca (akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6)
