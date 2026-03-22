# Akash Provider - Advertised Capabilities

**Provider:** reverb256.ca
**Region:** us-west
**Zone:** homelab
**Last Updated:** 2026-03-20

---

## 🖥️ Compute Resources

### GPU Inventory (Total: 5 GPUs)

| Node | GPU Model | Count | VRAM | Interface | Akash Label |
|------|-----------|-------|------|-----------|-------------|
| **zephyr** | RTX 3090 | 1 | 24GB | PCIe 3.0 | ✅ Labeled |
| **zephyr** | RTX 3060 Ti | 1 | 8GB | PCIe 3.0 | ✅ Labeled |
| **nexus** | RTX 3060 Ti | 1 | 8GB | PCIe 3.0 | ✅ Labeled |
| **forge** | RTX 4060 | 2 | 8GB each | PCIe 3.0 | ✅ Labeled |

**Total GPU Memory:** 56GB (24GB + 3×8GB)
**Total GPU Count:** 5 GPUs

### CPU Resources

| Node | CPU Cores | Memory | Status |
|------|-----------|--------|--------|
| zephyr | 12 cores | 64GB | Control-plane + GPU |
| nexus | 16 cores | 32GB | GPU + Storage |
| forge | 20 cores | 16GB | GPU + Mining |
| sentry | 30 cores | 11GB | Monitoring + Logging |

**Total Cluster:** 78 cores, 123GB RAM

---

## 💾 Storage Classes

All nodes support 3 storage classes for Akash deployments:

| Storage Class | Type | Reclaim Policy | Description |
|---------------|------|----------------|-------------|
| **beta2** | Local Path | Delete | Standard persistent storage |
| **beta3** | Local Path | Delete | Enhanced persistent storage |
| **ram** | Local Path | Delete | RAM-disk storage (fastest) |

**Availability:** All 4 nodes

---

## 🌐 Network & Region

| Attribute | Value |
|-----------|-------|
| **Region** | us-west |
| **Zone** | homelab |
| **Domain** | reverb256.ca |
| **Ingress Pattern** | *.ingress.reverb256.ca |
| **Dedicated DNS** | *.dedicated.ingress.reverb256.ca |

---

## 💰 Pricing (Bid Script)

### Financial Requirements

| Requirement | Amount | Status | Notes |
|-------------|--------|--------|-------|
| **Bid Deposit** | 500 AKT | ⚠️ **Verify on-chain** | 5 AKT × 100 max deployments |
| **Max Concurrent Deployments** | 100 | ✅ Configured | Cluster capacity |
| **Withdrawal Period** | 720 blocks | ✅ Active | ~72 minutes |
| **Provider Address** | akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6 | ✅ Active | Mainnet |

**Bid Deposit Verification:**
```bash
# Check current bid deposit on-chain
kubectl exec -n akash-services deployment/akash-provider -- \
  provider-services query provider akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6

# Or using Akash CLI (if installed)
provider-services query provider --node https://rpc.akashnet.net:443 \
  akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
```

**Bid Deposit Formula:**
```
Required Deposit = 5 AKT × (Max Concurrent Deployments)
                  = 5 AKT × 100
                  = 500 AKT (~$250 USD at $0.50/AKT)
```

**Why 5 AKT per deployment?**
This ensures the provider has enough AKT locked to cover transaction fees for all active bids. Without sufficient deposit, new bids will fail even if resources are available.

---

### GPU Pricing (uakt per block)

| GPU Model | Price (uakt/block) | Approx USD/hr |
|-----------|-------------------|---------------|
| RTX 3090 | 20,000 | ~$0.20 |
| RTX 4060 | 18,000 | ~$0.18 |
| RTX 3060 Ti | 15,000 | ~$0.15 |

### Base Pricing (per 1000 units)

| Resource | Price (uakt/block) |
|----------|-------------------|
| CPU | 1.5 |
| Memory | 0.8 |
| Storage | 0.02 |

**Minimum Bid:** 1 uakt/block (floor price)

### Pricing Optimization Strategy

**Current Utilization:** 0% (no active leases)

**Dynamic Pricing Rules:**
| Utilization | Action | Discount |
|-------------|--------|----------|
| < 30% | Lower prices | 25% discount |
| 30-60% | Maintain prices | No change |
| 60-90% | Raise prices | 25% premium |
| > 90% | Maximize prices | 50% premium |

**Current Pricing (Baseline):**
| GPU Model | Price (uakt/block) | With 25% Discount | Approx USD/hr |
|-----------|-------------------|-------------------|---------------|
| RTX 3090 | 20,000 | 15,000 | $0.15 |
| RTX 4060 | 18,000 | 13,500 | $0.135 |
| RTX 3060 Ti | 15,000 | 11,250 | $0.1125 |

**Recommendation:** Consider temporarily lowering prices to attract first tenants:
```nix
# In modules/services/akash-provider.nix
pricing = {
  rtx3090 = 15000;  # 20,000 → 15,000 uakt/block (25% discount)
  rtx4060 = 13500;  # 18,000 → 13,500 uakt/block
  rtx3060ti = 11250; # 15,000 → 11,250 uakt/block
};
```

**Trade-off:** Lower prices = higher lease win rate = build reputation → raise prices later

---

## 🔧 Provider Services

### Cluster Configuration

| Setting | Value |
|---------|-------|
| **Max Deployments** | 100 |
| **Memory Overcommit** | 0% (disabled) |
| **CPU Overcommit** | 0% (disabled) |
| **Withdrawal Period** | 720 blocks (~72 min) |

### Features

| Feature | Status |
|---------|--------|
| **IP Operator** | ❌ Disabled |
| **Persistent Storage** | ✅ Enabled |
| **Bid Engine** | ✅ Active |
| **gRPC Endpoint** | ✅ Available |

---

## 🌐 Provider Endpoints

### Public Endpoints

| Endpoint | URL | Purpose |
|----------|-----|---------|
| **Provider Bid Engine** | provider.reverb256.ca | REST API for bidding |
| **Provider gRPC** | grpc.provider.reverb256.ca | gRPC for lease management |
| **Status Dashboard** | status.provider.reverb256.ca | Health monitoring |
| **Status Page** | akash.reverb256.ca | Public status |

### Internal Endpoints (NodePort)

| Service | Protocol | NodePort | Target |
|---------|----------|----------|--------|
| Provider HTTPS | TCP | 30843 | 10.1.1.120:8443 |
| Provider gRPC | TCP | 30844 | 10.1.1.120:8444 |
| Provider HTTP | TCP | 30080 | 10.1.1.120:80 |

---

## 🏷️ Kubernetes Node Labels

### Zephyr (Control-plane + GPU)

```yaml
akash.network: "true"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx3090: "true"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx3060ti: "true"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx3090.interface.pcie: "1"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx3090.ram.24Gi: "1"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx3060ti.interface.pcie: "1"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx3060ti.ram.8Gi: "1"
akash.network/capabilities.storage.class.beta2: "1"
akash.network/capabilities.storage.class.beta3: "1"
akash.network/capabilities.storage.class.ram: "1"
nvidia.com/gpu.count: "2"
nvidia.com/gpu.product: "RTX3090"
topology.kubernetes.io/region: "us-west"
topology.kubernetes.io/zone: "homelab"
```

**GPUs:** 2x (RTX 3090 24GB + RTX 3060 Ti 8GB)

### Nexus (GPU + Storage)

```yaml
akash.network: "true"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx3060ti: "true"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx3060ti.interface.pcie: "1"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx3060ti.ram.8Gi: "1"
akash.network/capabilities.storage.class.beta2: "1"
akash.network/capabilities.storage.class.beta3: "1"
akash.network/capabilities.storage.class.ram: "1"
nvidia.com/gpu.count: "1"
nvidia.com/gpu.product: "RTX3060Ti"
topology.kubernetes.io/region: "us-west"
topology.kubernetes.io/zone: "homelab"
```

**GPUs:** 1x (RTX 3060 Ti 8GB)

### Forge (GPU + Mining)

```yaml
akash.network: "true"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx4060: "true"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx4060.interface.pcie: "2"
akash.network/capabilities.gpu.vendor.nvidia.model.rtx4060.ram.8Gi: "2"
akash.network/capabilities.storage.class.beta2: "1"
akash.network/capabilities.storage.class.beta3: "1"
akash.network/capabilities.storage.class.ram: "1"
nvidia.com/gpu.count: "2"
nvidia.com/gpu.product: "RTX4060"
topology.kubernetes.io/region: "us-west"
topology.kubernetes.io/zone: "homelab"
```

**GPUs:** 2x (RTX 4060 8GB each, 16GB total)

### Sentry (Monitoring)

```yaml
akash.network: "true"
akash.network/capabilities.storage.class.beta2: "1"
akash.network/capabilities.storage.class.beta3: "1"
akash.network/capabilities.storage.class.ram: "1"
topology.kubernetes.io/region: "us-west"
topology.kubernetes.io/zone: "homelab"
```

**GPUs:** None (CPU-only node)

---

## 🔒 Security & Compliance

### SSL/TLS Configuration

| Setting | Value | Status |
|---------|-------|--------|
| **SSL/TLS Mode** | Full (strict) | ✅ Applied |
| **Minimum TLS Version** | 1.2+ | ✅ Applied |
| **Certificate Authority** | Google | ✅ Active |

### Access Control

| Endpoint | Protection | Access |
|----------|------------|--------|
| Provider Bid Engine | Zero Trust | j_kroeker@reverb256.ca only |
| Provider gRPC | Zero Trust | j_kroeker@reverb256.ca only |
| Status Dashboard | Public | Unauthenticated |
| Tenant Ingress | Public | Unauthenticated |

---

## 📊 Provider Metrics

### Capacity

| Resource | Total | Available | Utilized |
|----------|-------|-----------|----------|
| GPUs | 5 | 5 | 0% |
| GPU Memory | 56GB | 56GB | 0% |
| CPU Cores | 78 | ~30 | ~38% |
| Memory | 123GB | ~80 | ~35% |

### Performance

| Metric | Value |
|--------|-------|
| **Network** | 10Gbps cluster interconnect |
| **Storage** | Local NVMe SSD |
| **GPU Bandwidth** | PCIe 3.0 (up to 16 GB/s) |
| **Latency** | <1ms intra-cluster |

---

## 🚀 Tenant Experience

### Deployment Features

| Feature | Description | Status |
|---------|-------------|--------|
| **Automated DNS** | Auto-creates tenant DNS records | ✅ Ready |
| **Cache Purging** | Auto-purges on deployment | ✅ Ready |
| **Prometheus Metrics** | Exports to Prometheus | ✅ Ready |
| **Health Dashboard** | Real-time status | ✅ Ready |
| **Public Ingress** | *.ingress.reverb256.ca | ✅ Active |
| **Dedicated DNS** | *.dedicated.ingress.reverb256.ca | ✅ Active |

### Storage Options

Tenants can choose from 3 storage classes:
- **beta2** - Standard persistent storage
- **beta3** - Enhanced persistent storage
- **ram** - RAM-disk (fastest, volatile)

### Supported GPU Models

Tenants can specifically request:
- **vendor: nvidia**
- **model: rtx3090** (24GB VRAM) - 1 available
- **model: rtx4060** (8GB VRAM) - 2 available (multi-GPU node)
- **model: rtx3060ti** (8GB VRAM) - 2 available (distributed across Zephyr + Nexus)

Example manifest:
```yaml
resources:
  gpu:
    vendor: nvidia
    model: rtx3090
    count: 1
```

---

## 📝 Provider Attributes Summary

### What Tenants See

When tenants query your provider, they see:

```yaml
attributes:
  region: us-west
  zone: homelab
  gpu:
    vendor: nvidia
    models:
      - rtx3090
      - rtx4060
      - rtx3060ti
  storage:
    - beta2
    - beta3
    - ram
  capabilities:
    - persistent-storage
    - gpu-acceleration
    - dedicated-dns
    - cache-purging
    - prometheus-metrics
    - health-dashboard
```

### Pricing Summary

| GPU | Price | Value Proposition |
|-----|-------|------------------|
| RTX 3090 | ~$0.20/hr | 24GB VRAM - High-end ML |
| RTX 4060 | ~$0.18/hr | 8GB VRAM x2 - Good value |
| RTX 3060 Ti | ~$0.15/hr | 8GB VRAM - Budget friendly |

---

## 🎯 Competitive Advantages

1. **High-End GPUs** - RTX 3090 with 24GB VRAM for large models
2. **Multiple GPU Options** - 3 different models for different use cases
3. **Fast Storage** - NVMe SSD with 3 storage classes
4. **Automated DNS** - Zero-config tenant DNS setup
5. **Real-time Metrics** - Prometheus integration
6. **Enterprise Security** - Full strict TLS + certificate validation
7. **Health Monitoring** - Real-time dashboard for tenants
8. **US West Region** - Low latency for West Coast tenants

---

## 📈 Scaling Potential

### Current Capacity
- **Max Concurrent GPU Deployments:** 4 (one per GPU)
- **Max Mixed Workloads:** ~10-20 (depending on GPU/CPU requirements)

### Future Expansion
- **Add more GPUs** to Forge (up to 4x RTX 4060)
- **Add GPU** to Sentry (if AMD support returns)
- **Add worker nodes** for CPU-only workloads
- **Increase storage** with distributed storage (Garage S3)

---

## 🔗 Quick Links

- **Provider Status:** https://status.provider.reverb256.ca
- **Documentation:** /etc/nixos/docs/akash-cloudflare-integration.md
- **Pricing Script:** /etc/nixos/etc/akash-provider/akash-provider-values.yaml
- **GPU Labels:** `kubectl get nodes --show-labels | grep akash`

---

**Version:** 1.0
**Last Updated:** 2026-03-20
**Provider Status:** Active (pending deployment)
**Chain ID:** akashnet-2
