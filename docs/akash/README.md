# Akash Provider

**Provider**: `akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6`
**Status**: ⚠️ Blocked - Incomplete hostname configuration
**Last Updated**: 2026-03-19

---

## Quick Start

### Current Status

| Component | Status | Notes |
|-----------|--------|-------|
| **GPU Nodes** | ✅ Labeled | 8 GPUs across 4 nodes |
| **Storage** | ✅ Bound | PV/PVC connected |
| **Hostname** | ❌ Incomplete | `provider.` - must configure domain |
| **Zone Labels** | ⚠️ Partial | Only zephyr labeled |

### Blocking Issue

Provider container crashes immediately due to incomplete hostname:
```yaml
AKASH_CLUSTER_PUBLIC_HOSTNAME: provider.  # INCOMPLETE
AKASH_DEPLOYMENT_INGRESS_DOMAIN: ingress.  # INCOMPLETE
```

**Required**: Set valid public hostname (e.g., `provider.example.com`)

---

## Infrastructure

### GPU Inventory

| Node | NVIDIA GPUs | AMD GPUs |
|------|-------------|----------|
| **zephyr** | RTX 3090, RTX 3060 Ti | - |
| **forge** | RTX 4060, RTX 4060 | RX 5700 XT, RX 5700 XT |
| **nexus** | RTX 3060 Ti | - |
| **sentry** | - | RX 5600 XT |
| **Total** | **5x NVIDIA** | **3x AMD** |

### Cluster Resources

- **CPUs**: 78 cores across 4 nodes
- **Memory**: 123GB total
- **Storage**: 2.9TB (after bind mount correction)
- **Network**: 1Gbps internal, regional latency tier

### Storage Configuration

```yaml
PV: akash-provider-home-pv-new (10Gi, local, Zephyr)
PVC: home-akash-provider-0 (Bound ✅)
StorageClass: akash-provider-local-static (WaitForFirstConsumer)
```

---

## Provider Configuration

### Bid Pricing Strategy

| Resource | Price | Market Position |
|----------|-------|-----------------|
| **CPU** | 0.004 uakt/millicore | Mid-range |
| **Memory** | 0.0016 uakt/MB | Mid-range |
| **Storage** | 0.00016 uakt/MB | Competitive |
| **IP Address** | 60 uakt | Standard |

**Bid Deposit**: 750,000 uakt (~$0.38)

### Resource Overcommitment

| Resource | Overcommit | Risk Level |
|----------|------------|------------|
| **CPU** | 10% | Low |
| **Memory** | 20% | Low |
| **Storage** | 0% | None (data safety) |
| **GPU** | 0% | None (performance) |

### Advertised Capabilities (18 total)

**GPU**: NVIDIA vendor, RTX 3060 Ti/3090/4060 models, 8GB/24GB VRAM
**Storage**: Beta2 (HDD), Beta3 (SSD), RAM (ephemeral), all persistent
**IPFS**: Pinning + gateway
**Databases**: PostgreSQL, MongoDB, Redis
**Video**: NVENC encoding, transcoding
**Rendering**: GPU-accelerated, Blender/Cycles
**Development**: Workspace hosting
**Blockchain**: Cosmos SDK node hosting
**AI/ML**: Inference + training
**Networking**: Public IP, 1Gbps bandwidth, regional latency
**Monitoring**: Prometheus + Grafana
**Provider**: Community tier, Reverb256 org, Canada/BC-West, x86_64

---

## Setup & Configuration

### Module Files

- `/etc/nixos/modules/services/akash-provider.nix` - Provider module
- `/etc/nixos/modules/services/cloudflared.nix` - Cloudflare Tunnel
- `/etc/nixos/secrets/cloudflared-token.age` - Encrypted tunnel token

### Required Configuration

```bash
# 1. Set valid hostname
kubectl patch cm akash-provider-main -n akash-provider --type=json \
  -p='[{"op": "replace", "path": "/data/AKASH_CLUSTER_PUBLIC_HOSTNAME", "value":"provider.YOUR_DOMAIN.com"}]'

# 2. Fix zone labels on non-zephyr nodes
kubectl label node forge topology.kubernetes.io/zone=homelab --overwrite
kubectl label node nexus topology.kubernetes.io/zone=homelab --overwrite
kubectl label node sentry topology.kubernetes.io/zone=homelab --overwrite

# 3. Verify provider is running
kubectl logs akash-provider-0 -n akash-provider --tail=100
```

### Environment Variables

```bash
# Chain Configuration
AKASH_CHAIN_ID=akashnet-2  # Mainnet (use sandbox-2 for testnet)
AKASH_NODE=https://rpc.akashnet.net:443
AKASH_FROM=akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6

# Cluster Configuration
AKASH_CLUSTER_K8S=true
AKASH_CLUSTER_NODE_PORT_QUANTITY=2500
AKASH_CLUSTER_PUBLIC_HOSTNAME=provider.YOUR_DOMAIN.com

# Bid Pricing
AKASH_BID_DEPOSIT=750000
AKASH_BID_PRICE_CPU_SCALE=0.004
AKASH_BID_PRICE_MEMORY_SCALE=0.0016
AKASH_BID_PRICE_STORAGE_SCALE=0.00016

# Overcommitment
AKASH_OVERCOMMIT_PCT_CPU=10
AKASH_OVERCOMMIT_PCT_MEM=20
```

---

## Operations

### Daily Health Checks

```bash
# 1. Provider health status
kubectl get pods -n akash-services | grep provider

# 2. Check provider logs for bid activity
kubectl logs akash-provider-0 -n akash-services --tail=100 | grep -E "bid|lease"

# 3. Monitor cluster utilization
kubectl top nodes

# 4. Check for active leases
kubectl get leases -n akash-services -o wide
```

### Performance Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Bid Success Rate** | >30% | `kubectl logs -n akash-services | grep "bid accepted" | wc -l` |
| **Lease Win Rate** | >20% | Provider console |
| **Cluster Utilization** | 60-80% | `kubectl top nodes` |
| **Uptime** | 99.5%+ | `kubectl logs -n akash-services --tail=-1` |

---

## Troubleshooting

### Provider Not Starting

**Symptom**: Container exits with code 1 after ~3 seconds

**Diagnosis**:
```bash
# Check logs
kubectl logs akash-provider-0 -n akash-provider --tail=100

# Check ConfigMap
kubectl get cm akash-provider-main -n akash-provider -o yaml | grep AKASH_CLUSTER_PUBLIC_HOSTNAME
```

**Solution**: Set valid `AKASH_CLUSTER_PUBLIC_HOSTNAME`

### Provider Not Winning Bids

**Symptoms**: Zero leases, low bid success rate

**Diagnosis**:
```bash
# Check current pricing
kubectl exec akash-provider-0 -n akash-provider -- printenv | grep AKASH_BID

# Compare with market rates
curl -s "https://api.akash.network/api/v1/leases" | jq '.[] | .price' | sort -n | head -20
```

**Solutions**:
1. Lower bid prices by 10-20% temporarily
2. Verify attributes are correctly advertised
3. Check provider is online and processing orders

### Overcommitment Issues

**Symptoms**: Performance degradation, OOM kills

**Diagnosis**:
```bash
# Check actual resource usage
kubectl top nodes
kubectl top pods -n akash-services
```

**Solutions**:
1. Reduce overcommitment percentages
2. Kill underperforming leases
3. Scale down provider bid acceptance

---

## References

### Akash Network Documentation
- [Provider Console](https://provider-console.akash.network/)
- [Hardware Requirements](https://akash.network/docs/providers/getting-started/hardware-requirements/)
- [Bid Pricing Calculation](https://akash.network/docs/providers/build-a-cloud-provider/akash-cli/akash-provider-bid-pricing-calculation/)

### Community Resources
- [Akash Provider Discord](https://discord.akash.network/)
- [GitHub Discussions](https://github.com/akash-network/discussions)

### Internal Documentation
- `STATUS.md` - Cluster status and recent changes
- `modules/compute-market/default.nix` - GPU auction engine configuration

---

**History**:
- 2026-03-19: Consolidated from 11 separate documents
- 2026-03-18: Provider deployment audit completed
- 2026-03-16: GPU node labeling verified
