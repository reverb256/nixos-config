# Akash Provider - Quick Status

**Last Updated**: 2026-03-20 10:35 UTC

## 🎯 Summary

| Metric | Value |
|--------|-------|
| **Status** | 🟡 **RUNNING - AWAITING VERIFICATION** |
| **Uptime** | Stable (provider restarts handled) |
| **CPU Usage** | ~67% (normal idle) |
| **Active Leases** | 0 (blocked by verification) |
| **Orders Processed** | Continuously (declined - awaiting verification) |

## 📋 Verification Status

**❌ NOT VERIFIED** - Attributes need x63 auditor signature

**Next Step**: Contact `@andy01` on [Akash Discord](https://discord.gg/akash)

```
Provider Address: akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6
Hostname: provider.reverb256.ca (fixed from provider.provider.reverb256.ca)
```

## 🖥️ Resources

| Node | CPU | GPU | RAM | Storage |
|------|-----|-----|-----|---------|
| forge | 6 cores | 2× RTX 4060 | 13GB | 206GB |
| nexus | 24 cores | 1× NVIDIA | 38GB | 823GB |
| sentry | 16 cores | 0 (CPU miner) | 26GB | 206GB |
| zephyr | 32 cores | 2× NVIDIA | 28GB | 837GB |
| **Total** | **78 cores** | **5 GPUs** | **111GB** | **2TB+** |

## ⛏️ Mining Status (Preemptible)

| Miner Type | Location | Priority | Monthly Revenue | Preemptible |
|------------|----------|----------|-----------------|-------------|
| GPU (NVIDIA) | forge | 100 | $60-100 | ✅ By Akash tenants |
| GPU (NVIDIA) | nexus | 100 | Part of above | ✅ By Akash tenants |
| GPU (NVIDIA) | zephyr | 100 | Part of above | ✅ By Akash tenants |
| CPU (xmrig) | sentry | N/A | Minimal | N/A (systemd) |

**Priority Order**: Akash tenants (800) > Gaming (500) > Mining (100)

## 📈 Pricing

```
CPU:     0.004 uakt/mCPU/s
Memory:  0.0016 uakt/MB/s
Storage: 0.00016 uakt/MB/s
IP:      60 uakt/IP/s
```

## 💰 Revenue Potential

| Scenario | Daily | Monthly |
|----------|-------|---------|
| **Mining (idle)** | $2-3 | $60-100 |
| **Akash Tenants (full utilization)** | $60-240 | $1,800-7,200 |
| **Hybrid (opportunistic)** | Variable | $60-7,200 |

## 🚀 Quick Commands

```bash
# Provider Status
ssh zephyr "kubectl exec -n akash-services akash-provider-akash-provider-fixed-0 -- curl -sk https://localhost:8443/status | jq ."

# Mining Status
ssh zephyr "kubectl get pods -n mining"
ssh sentry "systemctl status xmrig"

# GPU Availability
ssh zephyr "kubectl describe node forge | grep nvidia.com/gpu -A 2"

# Priority Classes
ssh zephyr "kubectl get priorityclass | grep -E 'akash|mining'"

# Test Preemption (deploy CPU workload)
kubectl apply -f /etc/nixos/kubernetes-manifests/akash/cpu-test-workload.yaml
```

## 📝 Notes

- Provider version: v0.10.7-v12
- All nodes detected correctly
- Bid pricing strategy configured
- DNS configured (provider.reverb256.ca)
- TLS certificate active
- **Preemption configured**: Miners auto-yield to Akash tenants
- **Mining revenue**: $60-100/month passive income when idle
- **Akash potential**: Up to $7,200/month when fully utilized

## Related Documentation

- [akash-provider-verification.md](./akash-provider-verification.md) - Verification guide
- [akash-mining-preemption.md](./akash-mining-preemption.md) - Preemption configuration
- [cpu-test-workload.yaml](../../kubernetes-manifests/akash/cpu-test-workload.yaml) - Test deployments
