# Kubernetes Intelligent Resource Allocation

## Overview
Autonomous, intelligent resource allocation system for the 4-node Kubernetes cluster using native Kubernetes capabilities.

## `★ Insight ─────────────────────────────────────`
**Three Layers of Autonomous Resource Management**

1. **LimitRange**: Sets default resource requests/limits for pods without them
   - Prevents "no limits" pods from consuming unlimited resources
   - Ensures fair allocation across namespaces

2. **ResourceQuota**: Caps total resource usage per namespace
   - Prevents one namespace from starving others
   - Enables multi-tenant resource isolation

3. **HorizontalPodAutoscaler**: Automatically scales replicas based on load
   - Uses metrics-server for real-time CPU/memory data
   - Configurable scale-up/scale-down policies
`─────────────────────────────────────────────────`

## Applied Configurations

### LimitRanges (Default Resources)
| Namespace | Default CPU | Default Memory | Max CPU | Max Memory |
|-----------|-------------|----------------|---------|------------|
| default | 100m | 128Mi | 4 | 8Gi |
| kube-system | 50m | 64Mi | 1 | 1Gi |
| ingress-system | 100m | 128Mi | 2 | 1Gi |
| akash-services | 50m | 64Mi | 2 | 2Gi |
| envoy-gateway-system | 100m | 256Mi | 2 | 1Gi |

### ResourceQuotas (Namespace Caps)
| Namespace | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|-------------|----------------|----------|--------------|
| default | 8 | 8Gi | 16 | 16Gi |
| kube-system | 4 | 4Gi | 8 | 8Gi |
| ingress-system | 2 | 2Gi | 4 | 4Gi |
| akash-services | 4 | 4Gi | 8 | 8Gi |
| envoy-gateway-system | 2 | 2Gi | 4 | 4Gi |

### HorizontalPodAutoscalers
| Workload | Min | Max | Scale Trigger |
|----------|-----|-----|---------------|
| caddy-ingress | 2 | 10 | CPU >70%, Mem >80% |
| cloudflared-tunnel | 1 | 5 | CPU >60%, Mem >75% |
| echo-server | 2 | 10 | CPU >50%, Mem >70% |

### PodDisruptionBudgets
- CoreDNS: minAvailable: 1
- Caddy Ingress: minAvailable: 1
- Kube-Flannel: maxUnavailable: 1
- Cloudflared Tunnel: minAvailable: 1

## Node Labels for Intelligent Scheduling

```
zephyr:   workload.ai=true, workload.control-plane=true
nexus:    workload.storage=true, workload.gpu=true
forge:    workload.mining=true, workload.gpu=true
sentry:   workload.monitoring=true
```

## Usage

### Check resource usage:
```bash
kubectl top nodes
kubectl top pods -A
kubectl get resourcequota -A
kubectl get limitrange -A
```

### Check HPA status:
```bash
kubectl get hpa -A
kubectl describe hpa caddy-ingress-hpa -n ingress-system
```

### Check PodDisruptionBudgets:
```bash
kubectl get pdb -A
```

## Files
- `/etc/nixos/kubernetes-manifests/resource-allocation/limit-range-default.yaml`
- `/etc/nixos/kubernetes-manifests/resource-allocation/resource-quota-default.yaml`
- `/etc/nixos/kubernetes-manifests/resource-allocation/hpa-scalers.yaml`
- `/etc/nixos/kubernetes-manifests/resource-allocation/pod-disruption-budgets.yaml`
- `/etc/nixos/kubernetes-manifests/resource-allocation/vpa-recommenders.yaml` (VPA not installed)
- `/etc/nixos/kubernetes-manifests/resource-allocation/intelligent-scheduling.yaml`

## Next Steps for Full Autonomy

1. **Install VPA (Vertical Pod Autoscaler)** for automatic resource request tuning
2. **Fix metrics-server** on all nodes for accurate HPA decisions
3. **Add cluster-autoscaler** for automatic node provisioning
4. **Install kube-prometheus-stack** for advanced resource monitoring
