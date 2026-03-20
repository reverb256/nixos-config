# Kubernetes Mining Migration - Complete Design

**Date**: 2026-03-20
**Status**: Design Phase
**Author**: Claude Sonnet 4.6 + Human

## Executive Summary

Migrate GPU mining workloads from systemd to Kubernetes with granular GPU scheduling, automatic gaming detection, and comprehensive observability. This enables **dynamic workload prioritization** where gaming preempts mining instantly.

## Current State Analysis

### ✅ What You Have
- **15 mining manifests** in `kubernetes-manifests/mining/`
- **Device plugins**: NVIDIA and AMD GPU support
- **Schedulers**: Volcano, Yunikorn configured
- **Priority classes**: Basic structure in `common/priority-classes.yaml`
- **Resource quotas**: GPU limits configured
- **Network policies**: Basic pod-to-pod allow rules
- **Agenix secrets**: 10+ secrets already managed (xmrig, context7, etc.)
- **Mining exporter**: `modules/services/mining-exporter.nix` (systemd only)
- **Gaming detection**: `modules/compute-market/auto-gaming-detection.sh`

### ❌ Critical Gaps

| Gap | Impact | Priority |
|-----|--------|----------|
| **No mining metrics in K8s** | No visibility into hashrate/power/temp | P0 |
| **No auto-scaling with gaming** | Mining continues during gaming (UX disaster) | P0 |
| **No secrets for K8s pods** | Wallet configs hardcoded in manifests | P0 |
| **No PodDisruptionBudgets** | All miners restart during upgrades | P1 |
| **No network policies for pools** | Miners can access anything | P1 |
| **No preemption mechanism** | Gaming can't evict mining | P1 |
| **No GPU validation webhook** | Miners might schedule on CPU-only nodes | P2 |

## Design Principles

1. **Security First**: Use agenix for all secrets, no hardcoded credentials
2. **User Experience**: Gaming always wins, mining auto-pauses
3. **Observability**: Every miner exposes metrics to Prometheus
4. **Resilience**: Graceful shutdowns, PDBs, health checks
5. **Consumer Hardware**: Optimize for RTX cards (no MIG, no datacenter features)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Gaming Detection (CronJob)                           │   │
│  │ - Checks Steam/Lutris processes on hosts             │   │
│  │ - Scales miners to 0 when gaming detected             │   │
│  │ - Uses priority class for instant preemption          │   │
│  └──────────────────────────────────────────────────────┘   │
│                           ↓                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Mining Pods (Priority: -10)                          │   │
│  │ - lolminer-nvidia (Forge)                            │   │
│  │ - lolminer-amd (Forge)                               │   │
│  │ - xmrig-proxy (Zephyr)                               │   │
│  │ - Expose metrics on :9101                             │   │
│  └──────────────────────────────────────────────────────┘   │
│                           ↓                                 │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Monitoring Stack                                      │   │
│  │ - Prometheus scrapes :9101/mining-metrics           │   │
│  │ - Grafana dashboards for hashrate/power/temp        │   │
│  │ - AlertManager: low hashrate, high temp alerts      │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  Secrets: agenix (wallets, pool configs)                   │
│  Network: Locked to mining pools + monitoring             │
└─────────────────────────────────────────────────────────────┘
```

## Component Designs

### 1. Mining Metrics Exporter (P0)

**Purpose**: Expose hashrate, power, temperature to Prometheus

**Implementation**: Port existing `modules/services/mining-exporter.nix` to K8s

```yaml
# kubernetes-manifests/mining/mining-exporter-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: mining-exporter
  namespace: mining
spec:
  selector:
    matchLabels:
      app: mining-exporter
  template:
    spec:
      hostNetwork: true  # Access localhost miner APIs
      containers:
      - name: exporter
        image: mining-exporter:latest
        ports:
        - containerPort: 9101
        env:
        - name: MINER_CONFIGS
          value: |
            lolminer: http://localhost:3333
            xmrig: http://localhost:3334
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: mining-exporter
  namespace: mining
  labels:
    app: mining-exporter
spec:
  selector:
    app: mining-exporter
  ports:
  - port: 9101
    targetPort: 9101
    name: metrics
```

**Metrics Exposed**:
- `mining_hashrate_mh{sminer="lolminer-nvidia",gpu="0"}`
- `mining_power_watts{miner="lolminer-nvidia",gpu="0"}`
- `mining_temperature_c{miner="lolminer-nvidia",gpu="0"}`
- `mining_shares_accepted_total{miner="lolminer-nvidia"}`
- `mining_uptime_seconds{miner="lolminer-nvidia"}`

### 2. Gaming-Aware Auto-Scaling (P0)

**Purpose**: Automatically pause mining when user starts gaming

**Implementation**: CronJob checks for gaming processes, scales miners

```yaml
# kubernetes-manifests/mining/gaming-pause-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: gaming-pause-checker
  namespace: mining
spec:
  schedule: "* * * * *"  # Every minute
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          hostNetwork: true  # Access host processes
          containers:
          - name: pause-checker
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - |
              # Check for gaming processes on host node
              NODE_NAME=$(cat /etc/hostname)

              # Detect Steam, Lutris, Heroic, etc.
              if pgrep -f "steam|lutris|heroic|wine.*\.exe" >/dev/null 2>&1; then
                echo "Gaming detected on $NODE_NAME, pausing miners"

                # Scale down all miners on this node
                kubectl scale deployment gpu-miner-$NODE_NAME --replicas=0 -n mining
                kubectl scale deployment xmrig-proxy --replicas=0 -n mining
              else
                echo "No gaming detected on $NODE_NAME, resuming miners"

                # Scale up miners
                kubectl scale deployment gpu-miner-$NODE_NAME --replicas=2 -n mining
                kubectl scale deployment xmrig-proxy --replicas=1 -n mining
              fi
```

**Alternative (Preferred)**: Use Prometheus alert to scale:

```yaml
# kubernetes-manifests/mining/gaming-alertmanager.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gaming-detection
  namespace: mining
spec:
  groups:
  - name: gaming.rules
    rules:
      # Trigger when gaming detected (custom metric from node-exporter)
      - alert: GamingDetected
        expr: gaming_processes{node="zephyr"} > 0
        for: 1m
        labels:
          severity: critical
          action: "scale_down_miners"
        annotations:
          summary: "Gaming detected, pausing mining"
```

### 3. Priority Classes for Preemption (P1)

**Purpose**: Gaming instantly preempts mining using priority classes

```yaml
# kubernetes-manifests/mining/mining-priority-classes.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: mining-background
value: -10  # Lower than default (0)
globalDefault: false
description: "Mining pods - lowest priority, preempted by everything"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: mining-paused
value: -100  # Even lower (for paused state)
globalDefault: false
description: "Paused miners - don't schedule"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: gaming-urgent
value: 1000  # Highest priority
globalDefault: false
description: "Gaming workload - preempts all mining"
```

**Apply to miners**:
```yaml
# In mining pod specs
spec:
  template:
    spec:
      priorityClassName: mining-background
```

### 4. Network Policies for Mining Pools (P1)

**Purpose**: Lock down miner network access to only necessary endpoints

```yaml
# kubernetes-manifests/mining/network-policies.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mining-egress
  namespace: mining
spec:
  podSelector:
    matchLabels:
      workload: mining
  policyTypes:
  - Egress
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53

  # Allow mining pools (whitelist approach)
  - to:
    - podSelector: {}  # Any pod
    ports:
    - protocol: TCP
      port: 3333  # lolminer
    - protocol: TCP
      port: 3334  # xmrig
    - protocol: TCP
      port: 14444 # stratum+tcp

  # Allow monitoring (Prometheus scraping)
  - to:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 9090

  # Allow xmrig-proxy API
  - to:
    - podSelector:
        matchLabels:
          app: xmrig-proxy
    ports:
    - protocol: TCP
      port: 8081
```

### 5. Secrets Management with Agenix (P0)

**Purpose**: Store wallet configs securely, no hardcoded credentials

**Current hardcoded wallets** (from manifests):
```yaml
# CURRENT (INSECURE):
value: "krxXVNVMM7.forge-gpu"
```

**New agenix secret**:

```bash
# Create agenix secret
# secrets/mining-wallets.age.nix
{
  "mining-wallets".age = {
    publicKeys = [ "age1..." ];  # Add your public keys
    secrets = {
      "forge-gpu" = "krxXVNVMM7.forge-gpu";
      "zephyr-gpu" = "krxXVNVMM7.zephyr-gpu";
      "nexus-gpu" = "krxXVNVMM7.nexus-gpu";
    };
  };
}
```

**Use in K8s**:
```yaml
# kubernetes-manifests/mining/mining-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: mining-wallets
  namespace: mining
type: Opaque
stringData:
  # These will be replaced by agenix in NixOS config
  forge-gpu: "FORGE_GPU_WALLET"
  zephyr-gpu: "ZEPHYR_GPU_WALLET"
  nexus-gpu: "NEXUS_GPU_WALLET"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mining-pools
  namespace: mining
data:
  pools.yml: |
    - url: stratum+tcp://xtm-c29-us.kryptex.network:8040
      wallet: $(WALLET_FORGE_GPU)
      pass: "x"
```

**NixOS integration** (inject secrets into manifests):
```nix
# modules/services/kubernetes/mining.nix
{
  # Agenix secrets for mining
  age.secrets.mining-wallets = {
    file = "${inputs.self}/secrets/mining-wallets.age";
    mode = "440";
    owner = "root";
  };

  # K8s secret injection
  environment.etc."kubernetes-manifests/mining/secrets.yaml".source =
    pkgs.writeText "mining-secrets.yaml" ''
      apiVersion: v1
      kind: Secret
      metadata:
        name: mining-wallets
        namespace: mining
      type: Opaque
      stringData:
        forge-gpu: "${config.age.secrets.mining-wallets.secrets.forge-gpu}"
        zephyr-gpu: "${config.age.secrets.mining-wallets.secrets.zephyr-gpu}"
    '';
}
```

### 6. PodDisruptionBudgets (P1)

**Purpose**: Keep some miners running during node maintenance

```yaml
# kubernetes-manifests/mining/pod-disruption-budgets.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: gpu-miner-forge-pdb
  namespace: mining
spec:
  minAvailable: 25%  # Keep 1 of 4 miners running
  selector:
    matchLabels:
      app: gpu-miner-forge
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: xmrig-proxy-pdb
  namespace: mining
spec:
  minAvailable: 1  # Always keep proxy running
  maxUnavailable: 0
  selector:
    matchLabels:
      app: xmrig-proxy
```

### 7. GPU Validation Webhook (P2)

**Purpose**: Prevent miners from scheduling on non-GPU nodes

```yaml
# kubernetes-manifests/scheduling/gpu-mining-validator.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: gpu-mining-validator
webhooks:
- name: validate-gpu-mining
  rules:
  - operations: ["CREATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  namespaceSelector:
    matchLabels:
      workload: mining
  failurePolicy: Deny
  sideEffects: None
  admissionReviewVersions: ["v1"]
  clientConfig:
    service:
      name: gpu-validator
      namespace: kube-system
      path: /validate
```

**Webhook logic** (Go):
```go
// Check if pod requests GPU but node has none
if pod.Spec.Containers[0].Resources.Limits.NvidiaGPU() > 0 {
    nodeHasGPU := getNodeGPUStatus(pod.Spec.NodeName)
    if !nodeHasGPU {
        return denied("Node does not have GPU resources")
    }
}
```

### 8. ServiceMonitor for Prometheus (P0)

**Purpose**: Automatically scrape mining metrics

```yaml
# kubernetes-manifests/mining/service-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mining-exporter
  namespace: mining
  labels:
    app: mining-exporter
spec:
  selector:
    matchLabels:
      app: mining-exporter
  endpoints:
  - port: metrics
    interval: 15s
    path: /metrics
```

### 9. Grafana Dashboard (Included)

**Purpose**: Visualize mining metrics

Already have `modules/compute-market/grafana-dashboard.json` - extend for K8s:
- Hashrate per GPU
- Power consumption trends
- Temperature alerts
- Uptime percentage
- Gaming vs mining time distribution

## Migration Strategy

### Phase 1: Foundation (Week 1)
1. Create mining secrets with agenix
2. Deploy mining exporter DaemonSet
3. Configure ServiceMonitor
4. Test metrics scraping

### Phase 2: Automation (Week 2)
1. Deploy gaming-pause CronJob
2. Configure priority classes
3. Test preemption mechanism
4. Verify gaming pauses mining

### Phase 3: Security (Week 2)
1. Implement network policies
2. Configure PodDisruptionBudgets
3. Deploy GPU validation webhook
4. Security audit

### Phase 4: Cutover (Week 3)
1. Migrate systemd miners to K8s
2. Verify hashrate stability
3. Monitor for 1 week
4. Decommission systemd miners

## Testing Checklist

- [ ] Secrets decrypt correctly in pods
- [ ] Metrics visible in Prometheus
- [ ] Gaming detection pauses miners
- [ ] Network policies don't break mining
- [ ] PDBs allow upgrades without downtime
- [ ] GPU webhook prevents bad scheduling
- [ ] Grafana dashboards populate
- [ ] Hashrate stable for 24 hours

## Rollback Plan

If K8s mining fails:
1. `kubectl scale deployment --replicas=0 -n mining` (stop all K8s miners)
2. `systemctl start mining-*` (resume systemd miners)
3. Investigate logs in `/var/log/mining/`
4. Fix issue, retry migration

## Success Criteria

- [ ] Gaming detection pauses mining within 60 seconds
- [ ] Mining resumes within 60 seconds after gaming stops
- [ ] All metrics visible in Grafana
- [ ] Zero hardcoded secrets in manifests
- [ ] Network policies allow mining pools
- [ ] PDBs allow node upgrades without 100% hashrate loss
- [ ] GPU webhook prevents scheduling on CPU-only nodes

## File Structure

```
kubernetes-manifests/mining/
├── 01-namespace.yaml
├── 02-secrets.yaml (managed by agenix)
├── 03-configmaps.yaml (pool configs)
├── 04-priority-classes.yaml
├── 05-network-policies.yaml
├── 06-metrics/
│   ├── mining-exporter-daemonset.yaml
│   └── service-monitor.yaml
├── 07-auto-scaling/
│   ├── gaming-pause-cronjob.yaml
│   └── scaling-rules.yaml
├── 08-miners/
│   ├── gpu-miner-forge.yaml
│   ├── gpu-miner-zephyr.yaml
│   └── xmrig-proxy.yaml
├── 09-pod-disruption-budgets.yaml
└── 10-validation/
    └── gpu-mining-validator-webhook.yaml
```

## Open Questions

1. **Gaming detection method**: CronJob (host processes) vs Prometheus (custom metrics)?
   - **Recommendation**: Start with CronJob, migrate to Prometheus if available

2. **Miner image strategy**: Use local Nix-built images or pull from registry?
   - **Recommendation**: Keep using local images (`imagePullPolicy: Never`)

3. **Multi-node mining**: Scale miners across all 4 nodes or keep node-specific?
   - **Recommendation**: Node-specific deployments (simpler, matches current setup)

## Next Steps

Upon approval:
1. Create all manifest files
2. Add agenix secrets for wallets
3. Deploy in phases (Foundation → Automation → Security → Cutover)
4. Monitor and validate each phase
5. Remove systemd miners after successful migration

---

**Ready for implementation?** Please review and approve, or provide feedback on any component.
