---
name: grafana
description: >
  Comprehensive Grafana expertise covering dashboard design, panel types, templating, alerts,
  provisioning, platform health dashboards, PromQL validation, and GitOps workflows.
  Use when building monitoring dashboards, visualizing metrics, creating operational insights,
  setting up SLO/SLI dashboards, or managing Kubernetes/OpenShift platform health.
risk: low
version: 1.0.0
---

# Grafana

Complete guide to Grafana dashboard creation, provisioning, platform health monitoring, and operational best practices.

## When to Use

- **Dashboard Creation**: Building monitoring dashboards for applications, infrastructure, or business metrics
- **Platform Health**: Kubernetes/OpenShift platform operations dashboards with tenant-impact prioritization
- **Visualization**: Visualizing time-series data from Prometheus, Loki, or other datasources
- **Alerts**: Setting up SLO/SLI dashboards with alert rules
- **Provisioning**: GitOps workflows, GrafanaDashboard CRs, Terraform provisioning
- **PromQL**: Query validation and optimization

## Dashboard Design Principles

### Hierarchy of Information

```
┌─────────────────────────────────────┐
│  Critical Metrics (Big Numbers)     │  ← Top row, immediate visibility
├─────────────────────────────────────┤
│  Key Trends (Time Series)           │  ← Middle, patterns over time
├─────────────────────────────────────┤
│  Detailed Metrics (Tables/Heatmaps) │  ← Bottom, drill-down capability
└─────────────────────────────────────┘
```

### Platform Health Priority (L1-L3 Architecture)

**L1 (Command View)**: Critical pre-tenant-impact signals only
- CO gate health
- Node status
- MCP (Multi-Cloud Proxy) status
- Core API/etcd/ingress health

**L2 (Platform Services)**: Dependency-domain grouped services
- Crossplane health
- Keycloak status
- Storage operators

**L3 (Deep Dives)**: Dedicated dashboards for specialized concerns
- GPU diagnostics (separate dashboard)
- Application-specific metrics

### RED Method (Services - Golden Signals)
- **Rate** - Requests per second
- **Errors** - Error rate (5xx, 4xx)
- **Duration** - Latency/response time (P50, P95, P99)

### USE Method (Resources)
- **Utilization** - % time resource is busy (CPU, memory, disk)
- **Saturation** - Queue length, wait time
- **Errors** - Error count, retry rate

## Panel Types

### 1. Stat Panel (Single Value)

```json
{
  "type": "stat",
  "title": "Total Requests",
  "targets": [{
    "expr": "sum(http_requests_total)"
  }],
  "options": {
    "reduceOptions": {
      "values": false,
      "calcs": ["lastNotNull"]
    },
    "orientation": "auto",
    "textMode": "auto",
    "colorMode": "value"
  },
  "fieldConfig": {
    "defaults": {
      "thresholds": {
        "mode": "absolute",
        "steps": [
          {"value": 0, "color": "green"},
          {"value": 80, "color": "yellow"},
          {"value": 90, "color": "red"}
        ]
      }
    }
  }
}
```

### 2. Time Series Graph

```json
{
  "type": "timeseries",
  "title": "CPU Usage",
  "targets": [{
    "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)"
  }],
  "yaxes": [
    {"format": "percent", "max": 100, "min": 0},
    {"format": "short"}
  ]
}
```

### 3. Table Panel

```json
{
  "type": "table",
  "title": "Service Status",
  "targets": [{
    "expr": "up",
    "format": "table",
    "instant": true
  }],
  "transformations": [
    {
      "id": "organize",
      "options": {
        "excludeByName": {"Time": true},
        "renameByName": {
          "instance": "Instance",
          "job": "Service",
          "Value": "Status"
        }
      }
    }
  ]
}
```

### 4. Heatmap

```json
{
  "type": "heatmap",
  "title": "Latency Heatmap",
  "targets": [{
    "expr": "sum(rate(http_request_duration_seconds_bucket[5m])) by (le)",
    "format": "heatmap"
  }],
  "dataFormat": "tsbuckets"
}
```

### 5. Gauge Chart

```json
{
  "type": "gauge",
  "title": "CPU Utilization",
  "targets": [{
    "expr": "avg by (instance) (100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100))"
  }],
  "fieldConfig": {
    "defaults": {
      "min": 0,
      "max": 100,
      "unit": "percent",
      "thresholds": {
        "steps": [
          {"value": 0, "color": "green"},
          {"value": 70, "color": "yellow"},
          {"value": 90, "color": "red"}
        ]
      }
    }
  }
}
```

## Variables & Templating

### Query Variables

```json
{
  "templating": {
    "list": [
      {
        "name": "datasource",
        "type": "datasource",
        "datasource": "Prometheus",
        "refresh": 1
      },
      {
        "name": "namespace",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(kube_pod_info, namespace)",
        "refresh": 1,
        "multi": false
      },
      {
        "name": "service",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(kube_service_info{namespace=\"$namespace\"}, service)",
        "refresh": 1,
        "multi": true,
        "includeAll": true,
        "allValue": ".*"
      }
    ]
  }
}
```

### Interval Variables

```json
{
  "name": "interval",
  "type": "interval",
  "query": "30s,1m,5m,10m,30m,1h,6h,12h,1d",
  "current": {
    "text": "auto",
    "value": "$__auto_interval"
  }
}
```

## Alerts

### Alert Configuration in Panel

```json
{
  "alert": {
    "name": "High Error Rate",
    "conditions": [
      {
        "evaluator": {
          "params": [5],
          "type": "gt"
        },
        "operator": {"type": "and"},
        "query": {
          "params": ["A", "5m", "now"]
        },
        "type": "query"
      }
    ],
    "executionErrorState": "alerting",
    "for": "5m",
    "frequency": "1m",
    "message": "Error rate is above 5% for 5 minutes",
    "noDataState": "no_data",
    "notifications": [
      {"uid": "slack-channel"}
    ]
  }
}
```

### Alert Best Practices

- Always set `for` duration to avoid alerting on spikes
- Include runbook links in alert messages
- Test alerts before deploying to production
- Use meaningful alert names that indicate the condition
- Every red panel must imply an action path

## Provisioning

### File-Based Provisioning

**/etc/grafana/provisioning/dashboards/dashboards.yml:**
```yaml
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: 'Production'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
```

**/etc/grafana/dashboards/my-dashboard.json:**
```json
{
  "dashboard": {
    "title": "My Dashboard",
    "tags": ["production"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [...]
  }
}
```

### Terraform Provisioning

```hcl
resource "grafana_dashboard" "api_monitoring" {
  config_json = file("${path.module}/dashboards/api-monitoring.json")
  folder      = grafana_folder.monitoring.id
}

resource "grafana_folder" "monitoring" {
  title = "Production Monitoring"
  uid    = "monitoring"
}
```

### Kubernetes ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboards
  namespace: monitoring
data:
  api-dashboard.json: |
    {
      "dashboard": {
        "title": "API Monitoring",
        ...
      }
    }
```

### OpenShift GrafanaDashboard CR

```yaml
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: platform-health
  namespace: monitoring
spec:
  json: |
    {
      "title": "Platform Health",
      "panels": [...]
    }
  instanceSelector:
  matchLabels:
    dashboards: "grafana"
```

## Platform Dashboard Workflow

### 1. Export Existing Dashboard

```bash
# From OpenShift/Kubernetes
oc --context <ctx> get grafanadashboard -A | rg -i '<dashboard-name>'

# Export dashboard JSON
skills/grafana-platform-dashboard/scripts/grafanadashboard_roundtrip.sh export \
  --context <ctx> \
  --namespace <ns> \
  --name <grafanadashboard-name> \
  --out-dir /tmp/<workspace>
```

### 2. Validate PromQL Queries

```bash
skills/grafana-platform-dashboard/scripts/promql_scan_thanos.sh \
  --context <ctx> \
  --dashboard-json /tmp/<workspace>/<name>.json
```

**Pass criteria**: All queries report `success`, zero bad/parse errors.

### 3. Apply Changes Live

```bash
skills/grafana-platform-dashboard/scripts/grafanadashboard_roundtrip.sh apply \
  --context <ctx> \
  --namespace <ns> \
  --name <grafanadashboard-name> \
  --json /tmp/<workspace>/<name>.json
```

### 4. Verify Sync Status

```bash
oc --context <ctx> -n <ns> get grafanadashboard <name> \
  -o jsonpath='{.status.conditions[?(@.type=="DashboardSynchronized")].status}{"|"}{.status.conditions[?(@.type=="DashboardSynchronized")].reason}{"\n"}'
```

### 5. Promote to GitOps

After live validation succeeds, commit changes to GitOps repository.

## PromQL Query Library

### Cluster Health

```promql
# Node readiness
count(kube_node_status_condition{condition="Ready", status="true"}) or vector(0)

# Pod status by namespace
count by (namespace) (kube_pod_status_phase{phase="Running"})

# API server latency
histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket[5m])) by (le))
```

### Resource Usage

```promql
# CPU utilization per node
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage per node
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100

# Disk usage
(node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes * 100
```

### Application Metrics

```promql
# Request rate (RED method)
sum(rate(http_requests_total{job="$app"}[5m]))

# Error rate
sum(rate(http_requests_total{job="$app",status=~"5.."}[5m])) /
sum(rate(http_requests_total{job="$app"}[5m])) * 100

# P95 latency
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
```

## Common Dashboard Patterns

### API Monitoring Dashboard

**Key Panels:**
- Request rate (RPS)
- Error rate % by status code
- P50, P95, P99 latency
- Active connections
- Queue length

### Infrastructure Dashboard

**Key Panels:**
- CPU utilization per node
- Memory usage per node
- Disk I/O and usage
- Network traffic
- Pod count by namespace
- Node status

### Database Dashboard

**Key Panels:**
- Queries per second
- Connection pool usage
- Query latency (P50, P95, P99)
- Active connections
- Database size
- Replication lag
- Slow query log

### Platform Dashboard (Kubernetes/OpenShift)

**Design Rules:**
1. Put critical tenant-impact predictors first
2. Every red panel must imply an action path
3. Keep L1 low-noise; move detail below
4. Filter noise from tools like ArgoCD when needed
5. Keep GPU diagnostics in dedicated dashboard

## Best Practices

### ✅ DO

- Use meaningful dashboard and panel titles
- Add description panels with context
- Implement row-based organization
- Use variables for dashboard flexibility
- Set appropriate refresh intervals (30s default)
- Include runbook links in alerts
- Test alerts before deploying
- Use consistent color schemes
- Version control dashboard JSON (GitOps)
- Configure proper units for metrics
- Start with Grafana community templates
- Group related metrics in rows
- Validate PromQL before applying
- Filter noise explicitly when needed

### ❌ DON'T

- Overload dashboards with too many panels (>20 is too many)
- Mix different time ranges without justification
- Create dashboards without documentation
- Ignore alert noise and fatigue
- Use inconsistent metric naming
- Set refresh too frequently (<10s causes load)
- Forget to configure datasources properly
- Leave default credentials
- Create giant monolithic dashboards
- Use decorative panels without purpose
- Mix GPU deep diagnostics into L1 platform dashboards
- Apply changes without PromQL validation

## Design Rules Summary

1. **Critical First**: Put tenant-impact predictors at the top
2. **Action-Oriented**: Every red panel must imply an action path
3. **Clear Naming**: Avoid ambiguous names (e.g., "platform pods" → "openshift-apiserver pods")
4. **Low Noise L1**: Keep command view minimal
5. **Segregated Deep Dives**: Specialized metrics go to dedicated dashboards

## Reference Implementations

### Minimal Dashboard Template

```json
{
  "dashboard": {
    "title": "Application Performance",
    "description": "Real-time application metrics",
    "tags": ["production", "performance"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": [
      {
        "title": "Request Rate",
        "type": "timeseries",
        "targets": [{
          "expr": "sum(rate(http_requests_total{service=\"$service\"}[5m]))",
          "legendFormat": "{{service}}"
        }],
        "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8}
      },
      {
        "title": "Error Rate %",
        "type": "timeseries",
        "targets": [{
          "expr": "(sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m]))) * 100"
        }],
        "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8}
      },
      {
        "title": "P95 Latency",
        "type": "timeseries",
        "targets": [{
          "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))"
        }],
        "gridPos": {"x": 0, "y": 8, "w": 24, "h": 8}
      }
    ]
  }
}
```

## Related Skills

- `prometheus-configuration` - For metric collection and query optimization
- `monitoring-observability` - For broader observability setup
- `kubernetes` - For Kubernetes/OpenShift platform understanding
