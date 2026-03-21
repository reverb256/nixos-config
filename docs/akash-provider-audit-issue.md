# [Provider Audit]: reverb256.ca

## Provider Information

- **Provider Address**: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
- **Provider Domain**: provider.reverb256.ca
- **Ingress Domain**: *.ingress.provider.reverb256.ca

## Contact Information

- **Name**: Reverb256 (Homelab)
- **Email**: admin@reverb256.ca
- **Website**: reverb256.ca
- **Location**: BC West, Canada (US West region)

## Provider Attributes (On-Chain)

```
attributes:
- key: host
  value: akash
- key: tier
  value: community
- key: organization
  value: Reverb256
- key: hardware-cpu-arch
  value: x86_64
- key: capabilities/gpu/vendor/nvidia
  value: "true"
- key: capabilities/gpu/vendor/nvidia/model/rtx3060ti
  value: "true"
- key: capabilities/gpu/vendor/nvidia/model/rtx3090
  value: "true"
- key: capabilities/gpu/vendor/nvidia/model/rtx4060
  value: "true"
- key: capabilities/gpu/vendor/nvidia/memory/8gb
  value: "true"
- key: capabilities/gpu/vendor/nvidia/memory/24gb
  value: "true"
- key: hardware-gpu
  value: rtx3060ti,rtx3090,rtx4060
- key: console/trials
  value: "true"
- key: capabilities/storage/1/class
  value: beta2
- key: capabilities/storage/1/persistent
  value: "true"
- key: capabilities/storage/2/class
  value: beta3
- key: capabilities/storage/2/persistent
  value: "true"
- key: capabilities/storage/3/class
  value: ram
- key: capabilities/storage/3/persistent
  value: "false"
- key: country
  value: Canada
- key: region
  value: bc-west
```

## Hardware Inventory

### Cluster Nodes (4 nodes)

**Forge** (GPU Computing + Mining):
- CPU: AMD Ryzen 9 5900X (24 threads)
- RAM: 64GB DDR4
- GPU: 2× NVIDIA RTX 4060 (8GB each)
- Storage: 2TB NVMe SSD
- Role: GPU workloads, mining

**Nexus** (Storage + GPU Computing):
- CPU: Intel Xeon E5-2678 v3 (48 threads)
- RAM: 256GB DDR4
- GPU: 1× NVIDIA (model TBD)
- Storage: 4TB HDD array
- Role: Storage, GPU computing

**Zephyr** (Control Plane + Gaming + AI):
- CPU: AMD Ryzen 9 7950X (32 threads)
- RAM: 128GB DDR4
- GPU: 2× NVIDIA (RTX 4090 or similar)
- Storage: 2TB NVMe SSD
- Role: Control plane, AI inference, gaming

**Sentry** (Monitoring + Logging):
- CPU: AMD Ryzen 7 5700G (16 threads)
- RAM: 64GB DDR4
- GPU: None
- Storage: 1TB NVMe SSD
- Role: Monitoring, logging, CPU mining

### Total Cluster Resources
- **CPU Cores**: 120 cores
- **Memory**: 512GB RAM
- **GPUs**: 5× NVIDIA (RTX 3060Ti, RTX 3090, RTX 4060 variants)
- **Storage**: 8TB+ SSD/HDD
- **Network**: 1Gbps fiber

## Prerequisites Verification

### ✅ 1. Provider Attributes
- **host**: akash ✅
- **tier**: community ✅
- **organization**: Reverb256 ✅
- **Contact Info**: admin@reverb256.ca ✅

### ⚠️ 2. DNS Resolution
- **Ingress Domain**: *.ingress.provider.reverb256.ca
- **Status**: Needs verification from external DNS
- **Note**: ConfigMap updated to `provider.reverb256.ca`, but blockchain `host_uri` still shows `provider.provider.reverb256.ca`

### ⚠️ 3. Port Accessibility
- **Port 8443**: Status endpoint accessible from cluster
- **Ports 80, 443, 8443, 8444**: Need external verification
- **Status**: Provider is responding internally

## Pricing

```
AKASH_BID_PRICE_CPU_SCALE: 0.004 uakt/mCPU/s
AKASH_BID_PRICE_MEMORY_SCALE: 0.0016 uakt/MB/s
AKASH_BID_PRICE_STORAGE_SCALE: 0.00016 uakt/MB/s
AKASH_BID_PRICE_IP_SCALE: 60 uakt/IP/hour
```

## Known Issues

### 🔴 High Priority
1. **Blockchain host_uri mismatch**: On-chain `host_uri` shows `provider.provider.reverb256.ca` but ConfigMap has correct `provider.reverb256.ca`
2. **Missing contact info on-chain**: `info.email` and `info.website` fields are empty in blockchain query

### 🟡 Medium Priority
1. **External DNS verification needed**: Cannot verify from internal network
2. **External port accessibility**: Need verification from outside cluster

## Notes

- Provider is online and actively processing orders
- Currently 0 active leases
- Provider version: v0.10.7-events-static
- Kubernetes cluster with YuniKorn scheduler for workload preemption
- Mining workloads yield to Akash tenants via priority classes (Akash: 800, Mining: 100)

## Audit Request

Please verify:
1. DNS resolution for `*.ingress.provider.reverb256.ca`
2. Port accessibility (80, 443, 8443, 8444) from external network
3. Provider attributes compliance with x63 auditor requirements
4. Recommendations for fixing blockchain `host_uri` and contact info

---

**Discord**: [Available upon request]
**Email**: admin@reverb256.ca
