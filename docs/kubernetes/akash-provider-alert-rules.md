# Prometheus Alert Rules for Akash Provider

**Purpose**: Monitor Akash provider health and prevent downtime
**Version**: 1.0
**Created**: 2026-03-22

---

## Alert Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: akash-provider-alerts
  namespace: akash-services
  labels:
    app: akash-provider
    severity: critical
spec:
  groups:
  - name: akash-provider-health
    interval: 30s
    rules:

    # Alert 1: Provider Pod Down
    - alert: AkashProviderPodDown
      expr: |
        kube_statefulset_status_replicas{namespace="akash-services", statefulset="akash-provider-akash-provider-fixed"}
        !=
        kube_statefulset_status_ready_replicas{namespace="akash-services", statefulset="akash-provider-akash-provider-fixed"}
      for: 5m
      labels:
        severity: critical
        component: provider
      annotations:
        summary: "Akash provider pod is down"
        description: "Provider pod has been down for more than 5 minutes ({{ $value }} replicas ready)"
        runbook: "https://docs.reverb256.ca/runbooks/akash-provider-recovery"

    # Alert 2: Provider Not Responding
    - alert: AkashProviderNotResponding
      expr: |
        up{job="akash-provider"} == 0
      for: 5m
      labels:
        severity: critical
        component: provider
      annotations:
        summary: "Akash provider is not responding"
        description: "Provider status endpoint has been unreachable for 5 minutes"
        runbook: "https://docs.reverb256.ca/runbooks/akash-provider-recovery"

    # Alert 3: Wallet Address Mismatch
    - alert: AkashProviderWalletMismatch
      expr: |
        akash_provider_address != "akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6"
      for: 1m
      labels:
        severity: critical
        component: provider
      annotations:
        summary: "Provider wallet address mismatch!"
        description: "Expected akash1c6h804ky08tdpnxrv72vum783xuey09qgzt2p6 but got {{ $value }}"
        runbook: "https://docs.reverb256.ca/runbooks/wallet-recovery"

    # Alert 4: Missing Node Inventory
    - alert: AkashProviderMissingInventory
      expr: |
        akash_provider_inventory_nodes < 4
      for: 10m
      labels:
        severity: warning
        component: provider
      annotations:
        summary: "Provider missing node inventory"
        description: "Only {{ $value }} nodes reporting inventory (expected 4: forge, nexus, sentry, zephyr)"

    # Alert 5: No GPUs Available
    - alert: AkashProviderNoGPUs
      expr: |
        akash_provider_inventory_gpus == 0
      for: 15m
      labels:
        severity: warning
        component: provider
      annotations:
        summary: "Provider has no GPUs available"
        description: "All GPUs are allocated or not reporting"

    # Alert 6: Provider Restart Loop
    - alert: AkashProviderRestartLoop
      expr: |
        increase(kube_pod_container_status_restarts_total{namespace="akash-services", pod=~"akash-provider-akash-provider-fixed-.*"}[1h]) > 5
      labels:
        severity: warning
        component: provider
      annotations:
        summary: "Provider pod is restarting frequently"
        description: "Provider has restarted {{ $value }} times in the last hour"

    # Alert 7: PVC Nearly Full
    - alert: AkashProviderPVCFillingUp
      expr: |
        kubelet_volume_stats_used_bytes{namespace="akash-services", persistentvolumeclaim=~"home-akash-provider.*"}
        /
        kubelet_volume_stats_capacity_bytes{namespace="akash-services", persistentvolumeclaim=~"home-akash-provider.*"} > 0.9
      for: 1h
      labels:
        severity: warning
        component: provider
      annotations:
        summary: "Provider PVC is 90% full"
        description: "Wallet data volume is {{ $value | humanizePercentage }} full"
```

---

## Metrics Required

These alerts require the following metrics:

### From kube-state-metrics:
- `kube_statefulset_status_replicas`
- `kube_statefulset_status_ready_replicas`
- `kube_pod_container_status_restarts_total`

### From cAdvisor:
- `kubelet_volume_stats_used_bytes`
- `kubelet_volume_stats_capacity_bytes`

### Custom metrics (need to create):
- `akash_provider_address` - Wallet address from /status endpoint
- `akash_provider_inventory_nodes` - Number of nodes reporting
- `akash_provider_inventory_gpus` - Total GPUs available
- `up{job="akash-provider"}` - From blackbox exporter

---

## Deployment

```bash
# Apply alert rules
kubectl apply -f kubernetes-manifests/monitoring/akash-provider-alerts.yaml

# Verify in Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/alerts
```

---

## Testing Alerts

### Test 1: Stop Provider Pod
```bash
kubectl scale statefulset akash-provider-akash-provider-fixed --replicas=0 -n akash-services
# Wait 5 minutes, should trigger: AkashProviderPodDown
kubectl scale statefulset akash-provider-akash-provider-fixed --replicas=1 -n akash-services
```

### Test 2: Block Provider Endpoint
```bash
# Temporarily block network access
kubectl exec -n akash-services akash-provider-akash-provider-fixed-0 -- iptables -A INPUT -p tcp --dport 8443 -j REJECT
# Should trigger: AkashProviderNotResponding after 5 minutes
kubectl exec -n akash-services akash-provider-akash-provider-fixed-0 -- iptables -D INPUT -p tcp --dport 8443 -j REJECT
```

---

## Alert Routing

Configure AlertManager to route these alerts:

```yaml
# alertmanager-config.yaml
receivers:
  - name: 'akash-provider-critical'
    webhook_configs:
      - url: 'https://hooks.example.com/akash-alerts'
    email_configs:
      - to: 'cluster-ops@reverb256.ca'
        subject: '🚨 CRITICAL: Akash Provider Alert'

route:
  receiver: 'akash-provider-critical'
  group_by: ['alertname', 'cluster']
  group_wait: 30s
  repeat_interval: 12h
  routes:
  - match:
      severity: critical
    receiver: 'akash-provider-critical'
    repeat_interval: 5m
```

---

## Dashboard Integration

Add these alerts to Grafana dashboard:
- Panel 1: Provider Status (Last 24h)
- Panel 2: Wallet Address Verification
- Panel 3: Node Inventory (4 nodes expected)
- Panel 4: GPU Availability (4 GPUs expected)
- Panel 5: PVC Usage Trend

---

**Next Steps**:
1. ✅ Create alert rules manifest
2. ⏳ Deploy blackbox exporter for provider endpoint monitoring
3. ⏳ Create custom metrics exporter for wallet address and inventory
4. ⏳ Configure AlertManager routing
5. ⏳ Test all alerts
6. ⏳ Create Grafana dashboard

**Owner**: Cluster Operations Team
**Review Date**: 2026-03-29
