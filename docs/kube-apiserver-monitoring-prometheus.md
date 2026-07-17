# Kube-API Server Monitoring - Using Prometheus

**Date:** 2026-03-21
**Status:** ✅ CONFIGURED
**Approach:** Prometheus-native monitoring (NOT custom systemd logger)

## Decision: Prometheus vs Custom Logger

### Why Prometheus Instead of Custom Systemd Service?

**Rejected Approach:** `modules/system/kube-apiserver-logger.nix`
- Custom systemd service watching PID changes
- Log file writing to `/var/log/kube-apiserver-restarts.log`
- Requires deployment to all nodes
- Separate log management and rotation
- Not integrated with existing monitoring stack

**Chosen Approach:** Prometheus-native monitoring
- ✅ Already configured and scraping API server metrics
- ✅ Centralized with all other cluster metrics
- ✅ Queriable via PromQL
- ✅ Integrates with AlertManager
- ✅ Grafana dashboards ready
- ✅ No additional deployment needed
- ✅ Historical data retention

## Current Configuration

### Prometheus Scrape Configuration

Prometheus is already scraping kube-apiserver from **two sources**:

1. **Static Configuration** (Primary)
   ```yaml
   - job_name: 'kube-apiserver-static'
     scheme: https
     static_configs:
       - targets: ['10.1.1.110:6443']  # Zephyr (control-plane)
   ```

2. **Kubernetes Service Discovery** (Backup)
   ```yaml
   - job_name: 'kubernetes-apiservers'
     kubernetes_sd_configs:
       - role: endpoints
   ```

### Available Metrics

Prometheus is collecting **100+ API server metrics** including:

#### Restart Detection
- `process_start_time_seconds{job="kube-apiserver-static"}` - Detects restarts (timestamp changes)
- `up{job="kube-apiserver-static"}` - API server availability (1=up, 0=down)

#### Performance Metrics
- `apiserver_request_total` - Total request count
- `apiserver_request_duration_seconds_bucket` - Request latency histogram
- `apiserver_storage_db_request_duration_seconds_bucket` - etcd latency
- `apiserver_longrunning_requests` - Active long-running requests

#### Error Tracking
- `apiserver_request_total{code=~"5.."}` - 5xx error rate
- `apiserver_audit_requests_rejected_total` - Authorization failures

#### Admission Control
- `apiserver_admission_step_admission_duration_seconds_bucket` - Admission latency

## Alert Rules Created

**File:** `kubernetes-manifests/monitoring/kube-apiserver-alerts.yaml`

### Active Alerts

| Alert | Severity | Condition | Description |
|-------|----------|-----------|-------------|
| **KubeAPIServerDown** | 🔴 Critical | `up == 0` for 1m | API server completely down |
| **KubeAPIServerRestarted** | 🟡 Warning | Uptime < 5 min | API server restarted recently |
| **KubeAPIServerLatencyHigh** | 🟡 Warning | P99 latency > threshold | Slow API responses |
| **KubeAPIServerErrorsHigh** | 🟡 Warning | 5xx rate > 5% | High error rate |
| **KubeAPIServerEtcdLatencyHigh** | 🟡 Warning | etcd P99 latency > threshold | Slow etcd operations |

### Alert Logic

**Restart Detection:**
```promql
# Detect restarts by checking process start time
time() - process_start_time_seconds{job="kube-apiserver-static"} < 300
```

This triggers when the API server has been running for less than 5 minutes, indicating a recent restart.

## Grafana Dashboard

**File:** `kubernetes-manifests/monitoring/grafana-dashboard-kube-apiserver.json`

### Dashboard Panels

1. **API Server Uptime** - Shows current uptime in seconds
   - Color coding: Green (>5min), Yellow (1-5min), Red (<1min)

2. **API Server Status** - UP/DOWN indicator
   - Background color: Green (UP), Red (DOWN)

3. **Requests per Second** - Request rate by verb (GET, POST, etc.)

4. **Request Latency (P99)** - 99th percentile response time by verb

5. **Error Rate (5xx)** - Server error rate over time

6. **etcd Request Latency (P99)** - Storage backend performance

7. **Active Long-Running Requests** - Watch/list operations in progress

8. **Admission Controller Latency** - Webhook/admission performance

### Loading the Dashboard

```bash
# Option 1: Import via Grafana UI
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open http://localhost:3000
# Dashboards -> Import -> Upload JSON file

# Option 2: Load via ConfigMap (automated)
kubectl create configmap grafana-dashboard-kube-apiserver \
  --from-file=kubernetes-manifests/monitoring/grafana-dashboard-kube-apiserver.json \
  -n monitoring
```

## Querying API Server Status

### Check Current Uptime
```bash
# Via Prometheus API
kubectl exec -n monitoring prometheus-<pod> -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=process_start_time_seconds{job=\"kube-apiserver-static\"}"

# Via kubectl exec
kubectl exec -n monitoring prometheus-<pod> -- \
  promtool query instant 'process_start_time_seconds{job="kube-apiserver-static"}'
```

### Detect Restarts (Last Hour)
```promql
# Show process start time changes
process_start_time_seconds{job="kube-apiserver-static"}

# Calculate current uptime
time() - process_start_time_seconds{job="kube-apiserver-static"}
```

### Monitor Real-Time
```bash
# Access Prometheus UI
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090

# Query: process_start_time_seconds{job="kube-apiserver-static"}
# Graph shows timestamp changes (restarts)
```

## Verification

### Verify Prometheus is Scraping
```bash
# Check target status
kubectl exec -n monitoring prometheus-<pod> -- \
  wget -qO- "http://localhost:9090/api/v1/targets" | \
  jq '.data.activeTargets[] | select(.labels.job=="kube-apiserver-static")'

# Expected output: "health": "up"
```

### Verify Metrics Available
```bash
# List all API server metrics
kubectl exec -n monitoring prometheus-<pod> -- \
  wget -qO- "http://localhost:9090/api/v1/label/__name__/values" | \
  grep -o '"apiserver_[^"]*"'
```

### Verify Alerts Loaded
```bash
# Check PrometheusRule exists
kubectl get prometheusrule -n monitoring kube-apiserver-health

# Check rules in Prometheus
kubectl exec -n monitoring prometheus-<pod> -- \
  wget -qO- "http://localhost:9090/api/v1/rules" | \
  jq '.data.groups[] | select(.name=="kube-apiserver")'
```

## Maintenance

### Updating Alert Rules
```bash
# Edit the rules
vim kubernetes-manifests/monitoring/kube-apiserver-alerts.yaml

# Apply changes
kubectl apply -f kubernetes-manifests/monitoring/kube-apiserver-alerts.yaml

# Prometheus auto-reloads rules (no restart needed)
```

### Updating Dashboard
```bash
# Import updated JSON via Grafana UI
# Or delete and recreate ConfigMap
kubectl delete configmap grafana-dashboard-kube-apiserver -n monitoring
kubectl create configmap grafana-dashboard-kube-apiserver \
  --from-file=kubernetes-manifests/monitoring/grafana-dashboard-kube-apiserver.json \
  -n monitoring
```

## Comparison: Custom Logger vs Prometheus

| Feature | Custom Logger | Prometheus |
|---------|--------------|------------|
| **Restart Detection** | ✅ PID watching | ✅ `process_start_time_seconds` |
| **Historical Data** | ❌ Log file only | ✅ Time-series database |
| **Alerting** | ❌ Requires external tool | ✅ AlertManager integrated |
| **Visualization** | ❌ Text logs only | ✅ Grafana dashboards |
| **Querying** | ❌ grep/log parsing | ✅ PromQL |
| **Centralization** | ❌ Per-node logs | ✅ Cluster-wide metrics |
| **Deployment** | ❌ NixOS rebuild | ✅ Already running |
| **Maintenance** | ❌ Log rotation needed | ✅ Automatic retention |
| **Integration** | ❌ Standalone | ✅ Monitoring stack |

## Cleanup: Removed Custom Logger

### Files Deleted
- ❌ `modules/system/kube-apiserver-logger.nix` (removed from imports)

### Why Removed
1. **Redundant**: Prometheus already has better coverage
2. **Scattered Data**: Logs separate from metrics
3. **No Alerting**: Would need additional integration
4. **Maintenance Overhead**: Log rotation, file management
5. **Deployment Required**: NixOS rebuild needed

## Next Steps

### Immediate
- [x] Create PrometheusRule for API server health
- [x] Create Grafana dashboard for API server metrics
- [ ] Import dashboard into Grafana
- [ ] Verify alerts in AlertManager

### Future Enhancements
- [ ] Add alert notifications (Slack, email)
- [ ] Create SLO dashboard for API server
- [ ] Add etcd health monitoring
- [ ] Correlate API server restarts with cluster events

## References

- **Prometheus Configuration**: Inside Prometheus pod at `/etc/prometheus/prometheus.yml`
- **Kubernetes API Server Metrics**: https://kubernetes.io/docs/concepts/cluster-administration/system-metrics/
- **Prometheus Operator**: https://prometheus-operator.dev/
- **Grafana Dashboards**: http://grafana.example.com/dashboards

---

**Migration Completed:** 2026-03-21
**Approach:** Prometheus-native (centralized monitoring)
**Status:** ✅ Production Ready
**Dependencies:** Prometheus (running), AlertManager (configured), Grafana (running)
