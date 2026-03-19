# Akash Provider Optimization Guide

**Last Updated:** 2026-03-19 | **Provider:** akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6

---

## Overview

This guide documents the optimizations applied to our Akash Network provider to improve competitiveness, increase lease win rate, and maximize revenue while maintaining reliability.

---

## Configuration Summary

### **Bid Pricing Strategy**

| Resource | Price | Market Position | Notes |
|----------|-------|-----------------|-------|
| **CPU** | 0.004 uakt/millicore | Competitive | Mid-range pricing |
| **Memory** | 0.0016 uakt/MB | Competitive | Mid-range pricing |
| **Storage (beta2)** | 0.00016 uakt/MB | Competitive | HDD persistent storage |
| **Storage (beta3)** | 0.00016 uakt/MB | Competitive | SSD persistent storage |
| **Storage (RAM)** | 0.00016 uakt/MB | Competitive | Ephemeral RAM |
| **IP Address** | 60 uakt | Standard | Public IP per lease |

**Bid Deposit**: 750,000 uakt (~$0.38) - Increased from 500k for perceived reliability

### **Resource Overcommitment**

| Resource | Overcommit | Effective Capacity Increase | Risk Level |
|----------|------------|---------------------------|------------|
| **CPU** | 10% | +10% more CPU sold | Low |
| **Memory** | 20% | +20% more RAM sold | Low |
| **Storage** | 0% | No overcommit | None (data safety) |

**Rationale**: Industry-standard overcommitment assumes not all tenants use 100% of allocated resources. Conservative settings prioritize reliability over maximum revenue.

### **Advertised Capabilities (18 total)**

#### **GPU Capabilities**
- `capabilities/gpu/vendor/nvidia` - NVIDIA GPU support
- `capabilities/gpu/vendor/nvidia/model/rtx3060ti` - RTX 3060 Ti (8GB)
- `capabilities/gpu/vendor/nvidia/model/rtx3090` - RTX 3090 (24GB)
- `capabilities/gpu/vendor/nvidia/model/rtx4060` - RTX 4060 (8GB)
- `capabilities/gpu/vendor/nvidia/memory/8gb` - 8GB VRAM
- `capabilities/gpu/vendor/nvidia/memory/24gb` - 24GB VRAM
- `hardware-gpu` - "rtx3060ti,rtx3090,rtx4060"

#### **Storage Capabilities**
- `capabilities/storage/1/class: beta2` - HDD persistent storage
- `capabilities/storage/1/persistent: true`
- `capabilities/storage/2/class: beta3` - SSD persistent storage
- `capabilities/storage/2/persistent: true`
- `capabilities/storage/3/class: ram` - Ephemeral RAM
- `capabilities/storage/3/persistent: false`

#### **IPFS Capabilities**
- `capabilities/ipfs/pinning: true` - IPFS content pinning
- `capabilities/ipfs/gateway: true` - IPFS gateway access

#### **Database Capabilities**
- `capabilities/database/postgresql: true` - PostgreSQL hosting
- `capabilities/database/mongodb: true` - MongoDB hosting
- `capabilities/database/redis: true` - Redis caching

#### **Video Processing**
- `capabilities/video/nvenc: true` - NVIDIA GPU encoding
- `capabilities/video/transcoding: true` - Video transcoding

#### **GPU Rendering**
- `capabilities/rendering/gpu: true` - GPU-accelerated rendering
- `capabilities/rendering/blender: true` - Blender/Cycles support

#### **Development Workspaces**
- `capabilities/development/workspace: true` - Dev environment hosting

#### **Blockchain Infrastructure**
- `capabilities/blockchain/cosmos-sdk: true` - Cosmos SDK node hosting

#### **AI/ML Infrastructure**
- `capabilities/ai/inference: true` - AI model inference
- `capabilities/ai/training: true` - ML model training

#### **Networking Capabilities** ⭐ NEW
- `capabilities/networking/public-ip: true` - Public IP available
- `capabilities/networking/bandwidth: 1Gbps` - Network bandwidth
- `capabilities/networking/latency-tier: regional` - Latency classification

#### **Monitoring Capabilities** ⭐ NEW
- `capabilities/monitoring/prometheus: true` - Prometheus metrics
- `capabilities/monitoring/grafana: true` - Grafana dashboards

#### **Provider Identity**
- `host: akash`
- `tier: community`
- `organization: Reverb256`
- `hardware-cpu-arch: x86_64`
- `country: Canada`
- `region: bc-west`

#### **Akash Console Features**
- `console/trials: true` - Console trial deployments enabled

---

## Transaction History

### **Initial Capability Expansion**
- **Transaction**: `0FA001FA48B72CA40158393A3E889B68F04DC993DE4EAB196137444A1BCDC566`
- **Block**: 26010250
- **Attributes Added**: 13 (IPFS, databases, video, rendering, development, blockchain, AI/ML)
- **Cost**: 3,445 uakt (~$0.0017)

### **Network & Monitoring Attributes**
- **Transaction**: `D7AE1424B43EC7DED69969EE2E571F826E717F33665C264F05CF906FF3CC46FD`
- **Block**: 26010300
- **Attributes Added**: 5 (networking public-ip, bandwidth, latency-tier, monitoring prometheus, monitoring grafana)
- **Cost**: 3,834 uakt (~$0.0019)

---

## Performance Metrics

### **Target Metrics**

| Metric | Current | Target | Measurement Method |
|--------|---------|--------|-------------------|
| **Bid Success Rate** | Monitoring | >30% | `kubectl logs -n akash-services | grep "bid accepted" | wc -l` |
| **Lease Win Rate** | Monitoring | >20% | Provider console |
| **Cluster Utilization** | ~40% | 60-80% | `kubectl top nodes` |
| **Revenue per GPU/hr** | $0.045 | $0.05-0.07 | Track Akash earnings |
| **Active Leases** | 0 | 2-5 | `kubectl get leases -n akash-services` |
| **Uptime** | 99%+ | 99.5%+ | `kubectl logs -n akash-services --tail=-1` |

### **Capacity Analysis**

#### **Hardware Capacity**
- **CPUs**: 78 cores across 4 nodes
- **Memory**: 123GB total
- **Storage**: 2.9TB (after bind mount correction)
- **GPUs**: 7 NVIDIA GPUs (3× RTX 3060 Ti, 1× RTX 3090, 3× RTX 4060)

#### **Effective Capacity (with overcommitment)**
- **CPUs**: 78 cores × 110% = ~86 cores
- **Memory**: 123GB × 120% = ~148GB
- **Storage**: 2.9TB (no overcommit for data safety)
- **GPUs**: 7 GPUs (no overcommit - performance critical)

---

## Monitoring & Maintenance

### **Daily Checks**

```bash
# 1. Provider health status
kubectl get pods -n akash-services | grep provider

# 2. Check provider logs for bid activity
kubectl logs akash-provider-akash-provider-fixed-0 -n akash-services --tail=100 | grep -E "bid|lease"

# 3. Monitor cluster utilization
kubectl top nodes

# 4. Check for active leases
kubectl get leases -n akash-services -o wide

# 5. Verify provider configuration
kubectl exec akash-provider-akash-provider-fixed-0 -n akash-services -- printenv | grep AKASH_BID
```

### **Weekly Reviews**

```bash
# 1. Analyze bid success rate
kubectl logs akash-provider-akash-provider-fixed-0 -n akash-services --since=168h | grep "bid accepted" | wc -l

# 2. Check provider on-chain status
kubectl exec akash-provider-akash-provider-fixed-0 -n akash-services -- provider-services query provider get akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6 -o text

# 3. Review competitor pricing
curl -s "https://api.akash.network/api/v1/leases" | jq '.[] | {price, attributes}' | sort

# 4. Calculate revenue metrics
# Track Akash earnings vs mining revenue
```

### **Monthly Optimizations**

1. **Review Pricing Strategy**: Adjust bid pricing based on utilization
2. **Update Attributes**: Add new capabilities as infrastructure evolves
3. **Performance Tuning**: Adjust overcommitment ratios based on actual usage patterns
4. **Documentation**: Update this guide with learnings and optimizations

---

## Troubleshooting

### **Provider Not Winning Bids**

**Symptoms**: Zero leases, low bid success rate

**Diagnosis**:
```bash
# Check current pricing
kubectl exec akash-provider-akash-provider-fixed-0 -n akash-services -- printenv | grep AKASH_BID

# Compare with market rates
curl -s "https://api.akash.network/api/v1/leases" | jq '.[] | .price' | sort -n | head -20
```

**Solutions**:
1. Lower bid prices by 10-20% temporarily
2. Verify attributes are correctly advertised
3. Check provider is online and processing orders
4. Ensure sufficient capacity is available

### **Overcommitment Issues**

**Symptoms**: Performance degradation, OOM kills

**Diagnosis**:
```bash
# Check actual resource usage
kubectl top nodes
kubectl top pods -n akash-services

# Check for memory pressure
kubectl describe nodes | grep -A 5 "MemoryPressure"
```

**Solutions**:
1. Reduce overcommitment percentages
2. Kill underperforming leases
3. Scale down provider bid acceptance
4. Monitor tenant resource usage more closely

### **Configuration Drift**

**Symptoms**: ConfigMap changes not applied to provider

**Diagnosis**:
```bash
# Verify ConfigMap
kubectl get configmap akash-provider-akash-provider-fixed-main -n akash-services -o yaml | grep AKASH_BID_DEPOSIT

# Check provider environment
kubectl exec akash-provider-akash-provider-fixed-0 -n akash-services -- printenv | grep AKASH_BID_DEPOSIT
```

**Solutions**:
1. Restart provider pod to pick up ConfigMap changes
2. Verify StatefulSet references correct ConfigMap
3. Check for conflicting env vars in deployment

---

## Revenue Optimization

### **Current Revenue Streams**

| Source | Monthly Revenue | Margin | Notes |
|--------|-----------------|--------|-------|
| **Kubernetes (internal)** | $12,775 | 90% | AI inference workloads |
| **Akash GPU Leases** | $230 | 85% | Potential at market rates |
| **Mining** | $96 | 95% | Baseline passive income |
| **Specialized Workloads** | $680-2,150 | 70-80% | IPFS, databases, rendering |

### **Revenue Maximization Strategies**

#### **Short-term (1-3 months)**
1. **Competitive Pricing**: Maintain current pricing (mid-range)
2. **Attribute Expansion**: ✅ Already implemented (18 capabilities)
3. **Reliability Focus**: Maintain 99%+ uptime for repeat business

#### **Medium-term (3-6 months)**
1. **Dynamic Pricing**: Adjust prices based on cluster utilization
2. **Template Library**: Create one-click deploy templates for specialized workloads
3. **Community Building**: Participate in Akash Discord, share learnings

#### **Long-term (6-12 months)**
1. **Provider Branding**: Build reputation for reliability and specialized capabilities
2. **Managed Services**: Offer premium managed database and IPFS services
3. **Geographic Expansion**: Consider multi-region deployment

---

## Security Considerations

### **Resource Isolation**
- **Kubernetes namespaces**: Each tenant in isolated namespace
- **Resource limits**: CPU, memory, storage quotas enforced
- **Network policies**: Tenant-to-tenant network isolation

### **Data Protection**
- **No storage overcommit**: Zero overcommit for data safety
- **Persistent storage**: Beta2 (HDD) and Beta3 (SSD) with persistence
- **Backup strategy**: NFS shared storage for critical data

### **Provider Security**
- **Bid deposit**: Prevents spam bidding, shows commitment
- **Key management**: Test keyring backend for provider operations
- **TLS certificates**: Automatic certificate refresh via `refresh_provider_cert.sh`

---

## Future Enhancements

### **Planned Improvements**

1. **AEP-41 Implementation** (Q2 2025)
   - Automatic inventory-based attribute detection
   - More trusted attributes (tenant-verifiable)
   - Reduced manual attribute management

2. **Dynamic Pricing Script**
   - Utilization-based price adjustment
   - Competitor price monitoring
   - Automated bid optimization

3. **Specialized Templates**
   - IPFS pinning service template
   - PostgreSQL managed service template
   - GPU rendering farm template
   - Development workspace template

4. **Monitoring Dashboard**
   - Grafana dashboard for provider metrics
   - Bid success rate tracking
   - Revenue analytics
   - Competitor price comparison

5. **Multi-Region Expansion**
   - Deploy in multiple geographic regions
   - Attribute-based routing
   - Latency-optimized tenant placement

---

## References

### **Akash Network Documentation**
- [Provider Console](https://provider-console.akash.network/)
- [Provider Hardware Requirements](https://akash.network/docs/providers/getting-started/hardware-requirements/)
- [Should I Run an Akash Provider?](https://akash.network/docs/providers/getting-started/should-i-run-a-provider/)
- [Bid Pricing Calculation](https://akash.network/docs/providers/build-a-cloud-provider/akash-cli/akash-provider-bid-pricing-calculation/)

### **Community Resources**
- [Akash Provider Discord](https://discord.akash.network/)
- [GitHub Discussions](https://github.com/akash-network/discussions)
- [Reddit r/akashnetwork](https://www.reddit.com/r/akashnetwork/)

### **Internal Documentation**
- `STATUS.md` - Cluster status and recent changes
- `modules/compute-market/default.nix` - GPU auction engine configuration
- `hosts/*/configuration.nix` - Per-host provider settings

---

## Appendix: Configuration Files

### **Provider Environment Variables**
```bash
# Bid Pricing
AKASH_BID_DEPOSIT=750000uakt
AKASH_BID_PRICE_CPU_SCALE=0.004
AKASH_BID_PRICE_MEMORY_SCALE=0.0016
AKASH_BID_PRICE_STORAGE_SCALE=0.00016,beta2=0.00016
AKASH_BID_PRICE_IP_SCALE=60
AKASH_BID_PRICE_STRATEGY=shellScript

# Overcommitment
AKASH_OVERCOMMIT_PCT_CPU=10
AKASH_OVERCOMMIT_PCT_MEM=20
AKASH_OVERCOMMIT_PCT_STORAGE=0

# Provider Identity
AKASH_FROM=akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
AKASH_CHAIN_ID=akashnet-2
AKASH_NODE=https://rpc.akashnet.net:443

# Cluster Configuration
AKASH_CLUSTER_K8S=true
AKASH_CLUSTER_NODE_PORT_QUANTITY=2500
AKASH_CLUSTER_PUBLIC_HOSTNAME=provider.provider.reverb256.ca
```

### **Provider Attributes (On-Chain)**
```yaml
attributes:
  # GPU Capabilities
  - key: capabilities/gpu/vendor/nvidia/model/rtx3060ti
  - key: capabilities/gpu/vendor/nvidia/model/rtx3090
  - key: capabilities/gpu/vendor/nvidia/model/rtx4060

  # Storage Capabilities
  - key: capabilities/storage/1/class: beta2
  - key: capabilities/storage/2/class: beta3
  - key: capabilities/storage/3/class: ram

  # IPFS, Databases, Video, Rendering, Development, Blockchain, AI/ML
  # (18 total attributes - see full list above)
```

---

**Document Version**: 1.0 | **Last Review**: 2026-03-19
