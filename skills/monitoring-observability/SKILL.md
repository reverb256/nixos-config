---
name: monitoring-observability
description: Comprehensive monitoring, dashboards, and observability expertise. Covers Grafana dashboard creation, Prometheus configuration, monitoring architecture, alerting, metrics collection, PromQL queries, structured logging, and observability best practices. Use for setting up monitoring, creating dashboards, configuring Prometheus, or building observability stacks for applications and infrastructure.
sasmp_version: "1.3.0"
bonded_agent: 03-devops-engineer
bond_type: PRIMARY_BOND
skill_version: "3.0.0"
last_updated: "2025-01"
complexity: intermediate
estimated_mastery_hours: 100
prerequisites: [python-programming, containerization]
unlocks: [mlops, cloud-platforms]
---

# Monitoring & Observability

Production monitoring with Prometheus, Grafana, structured logging, alerting, and observability best practices for applications and infrastructure.

## When to Use

- **Dashboard Creation**: Building Grafana dashboards for metrics visualization
- **Prometheus Setup**: Configuring Prometheus for metrics collection
- **Monitoring Architecture**: Designing monitoring strategies and architectures
- **Observability**: Setting up logs, metrics, and tracing
- **Alerting**: Configuring alerts and alert routing with Alertmanager
- **Metrics Collection**: Instrumenting applications with Prometheus metrics
- **Kubernetes Monitoring**: Setting up K8s monitoring with ServiceMonitors
- **Performance Analysis**: Using PromQL for query and analysis
- **Infrastructure Monitoring**: Tracking system health, performance metrics, resource utilization

## The Three Pillars of Observability

```
┌─────────────────────────────────────────────────────────────┐
│                      OBSERVABILITY                        │
├──────────────┬──────────────┬──────────────┬──────────────┤
│   METRICS    │     LOGS      │    TRACES     │     EVENTS    │
│ (Prometheus)  │   (Loki)     │  (Tempo/Jaeger) │  (User/Action) │
├──────────────┴──────────────┴──────────────┴──────────────┤
│                    GRAFANA                             │
│               (Visualization & Alerting)                      │
└─────────────────────────────────────────────────────────────┘
```

### Metric Types (RED Method)

| Type | Purpose | Example |
|------|---------|---------|
| **R**ate | Requests per second | `rate(http_requests_total[5m])` |
| **E**rrors | Error rate, 5xx percentage | `rate(errors_total[5m])` |
| **D**uration | Latency (P95, P99) | `histogram_quantile(0.95, ...)` |
| **Saturation** | Resource usage | CPU, memory, disk usage |

## Prometheus Setup

### Docker Deployment

```yaml
# docker-compose.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:v2.48.0
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./rules:/etc/prometheus/rules
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'

  alertmanager:
    image: prom/alertmanager:v0.27.0
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
      - alertmanager-data:/alertmanager

  grafana:
    image: grafana/grafana:10.3.0
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_INSTALL_PLUGINS=grafana-piechart-panel

volumes:
  prometheus-data:
  alertmanager-data:
  grafana-data:
```

### Prometheus Configuration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'production'
    datacenter: 'us-east-1'

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets:
          - 'node-exporter:9100'

  - job_name: 'applications'
    static_configs:
      - targets:
          - 'app1:8080'
          - 'app2:8080'
    metrics_path: /metrics
    scrape_interval: 30s

  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
        replacement: $1
```

### Kubernetes Deployment with Helm

```bash
# Add Prometheus community Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack (includes Prometheus, Grafana, Alertmanager)
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin \
  --set prometheus.prometheusSpec.retention=15d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=gp3
```

### ServiceMonitor for Kubernetes

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
      scheme: http
  namespaceSelector:
    matchNames:
      - default
```

## Application Instrumentation

### Python Application

```python
from prometheus_client import Counter, Histogram, Gauge, start_http_server
import structlog
import time

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer()
    ]
)
logger = structlog.get_logger()

# Prometheus metrics
RECORDS_PROCESSED = Counter('records_processed_total', 'Total records processed', ['pipeline', 'status'])
PROCESSING_TIME = Histogram('processing_duration_seconds', 'Processing duration', ['pipeline'])
QUEUE_SIZE = Gauge('queue_size', 'Current queue size', ['queue_name'])

def process_batch(batch: list, pipeline_name: str):
    start_time = time.time()

    try:
        for record in batch:
            # Process record...
            RECORDS_PROCESSED.labels(pipeline=pipeline_name, status='success').inc()

        duration = time.time() - start_time
        PROCESSING_TIME.labels(pipeline=pipeline_name).observe(duration)

        logger.info("batch_processed",
            pipeline=pipeline_name,
            count=len(batch),
            duration_seconds=duration
        )

    except Exception as e:
        RECORDS_PROCESSED.labels(pipeline=pipeline_name, status='error').inc()
        logger.error("batch_failed", pipeline=pipeline_name, error=str(e), exc_info=True)
        raise

# Start metrics server
start_http_server(8000)
```

### Go Application

```go
import (
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
    "net/http"
)

var httpRequests = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "http_requests_total",
        Help: "Total HTTP requests",
    },
    []string{"method", "endpoint", "status"},
)

func init() {
    prometheus.MustRegister(httpRequests)
}

// Expose metrics endpoint
func main() {
    http.Handle("/metrics", promhttp.Handler())
    http.ListenAndServe(":8080", nil)
}
```

### Node.js Application

```javascript
const client = require('prom-client');

const httpRequests = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'endpoint', 'status']
});

// Middleware
app.use((req, res, next) => {
  res.on('finish', () => {
    httpRequests.inc({
      method: req.method,
      endpoint: req.path,
      status: res.statusCode
    });
  });
  next();
});

// Expose metrics
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});
```

## PromQL Queries

### Basic Queries

```promql
# Current CPU usage
node_cpu_seconds_total{mode="idle"}

# Rate of HTTP requests per second
rate(http_requests_total[5m])

# Average response time
avg(http_request_duration_seconds_sum / http_request_duration_seconds_count)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Error rate
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
```

### Aggregations

```promql
# Sum requests by status code
sum by (status_code) (rate(http_requests_total[5m]))

# Average CPU by instance
avg by (instance) (rate(node_cpu_seconds_total{mode!="idle"}[5m]))

# Top 5 endpoints by request count
topk(5, sum by (endpoint) (rate(http_requests_total[5m])))

# 95th percentile latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Sum across multiple labels
sum without (instance) (rate(http_requests_total[5m]))

# Count unique values
count by (environment) (up)
```

### Time-Based Queries

```promql
# Compare to 1 hour ago
http_requests_total - http_requests_total offset 1h

# Predict disk space in 4 hours
predict_linear(node_filesystem_avail_bytes[1h], 4 * 3600)

# Changes in last 5 minutes
changes(up[5m])

# Average over 24 hours
avg_over_time(http_requests_total[24h])

# Maximum over last hour
max_over_time(cpu_usage[1h])

# Rate of increase
increase(http_requests_total[1h])
```

## Alerting Rules

### Prometheus Alerting Rules

```yaml
# rules/alerts.yml
groups:
  - name: application
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m]))
          / sum(rate(http_requests_total[5m])) > 0.05
        for: 5m
        labels:
          severity: critical
          team: backend
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }}"

      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.instance }} is down"
          description: "Service has been down for more than 1 minute"

      - alert: HighMemoryUsage
        expr: |
          (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is {{ $value | humanizePercentage }}"

      - alert: DiskSpaceLow
        expr: |
          (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space low on {{ $labels.instance }}"
          description: "Only {{ $value | humanizePercentage }} disk space remaining"

      - alert: PipelineStalled
        expr: sum(rate(records_processed_total[10m])) == 0
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Data pipeline is not processing records"
          description: "No records processed in the last 10 minutes"

      - alert: HighLatency
        expr: histogram_quantile(0.95, rate(processing_duration_seconds_bucket[5m])) > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High processing latency detected"
          description: "P95 latency is {{ $value }}s"
```

### Recording Rules

```yaml
# rules/recording.yml
groups:
  - name: aggregations
    interval: 30s
    rules:
      - record: job:http_requests:rate5m
        expr: sum by (job) (rate(http_requests_total[5m]))

      - record: instance:node_cpu:avg_rate5m
        expr: |
          avg by (instance) (
            rate(node_cpu_seconds_total{mode!="idle"}[5m])
          )

      - record: job:http_latency:p95
        expr: |
          histogram_quantile(0.95,
            sum by (job, le) (rate(http_request_duration_seconds_bucket[5m]))
          )
```

## Alertmanager Configuration

```yaml
# alertmanager.yml
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/xxx'
  pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'

route:
  receiver: 'slack-notifications'
  group_by: ['alertname', 'severity', 'team']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'
    - match:
        severity: warning
      receiver: 'slack-notifications'

receivers:
  - name: 'slack-notifications'
    slack_configs:
      - channel: '#alerts'
        send_resolved: true
        title: '{{ .Status | toUpper }}: {{ .CommonLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'

  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: 'xxx'
        severity: critical
```

## Grafana Dashboards

### Dashboard JSON Structure

```json
{
  "dashboard": {
    "title": "Application Metrics Dashboard",
    "panels": [
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total[5m])) by (status_code)",
            "legendFormat": "{{ status_code }}"
          }
        ],
        "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8}
      },
      {
        "title": "Latency P95",
        "type": "gauge",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"
          }
        ],
        "gridPos": {"x": 12, "y": 0, "w": 6, "h": 8}
      },
      {
        "title": "Error Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{status=~'5..'}[5m])) / sum(rate(http_requests_total[5m])) * 100",
            "legendFormat": "Error %"
          }
        ],
        "gridPos": {"x": 0, "y": 8, "w": 6, "h": 4}
      }
    ]
  }
}
```

### Provisioning Dashboards

```yaml
# grafana/provisioning/dashboards/dashboards.yml
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
```

### Data Source Provisioning

```yaml
# grafana/provisioning/datasources/prometheus.yml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: 15s
      queryTimeout: 60s
```

## Structured Logging

```python
import structlog

# Configure structlog
structlog.configure(
    processors=[
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.PrintLoggerFactory(),
)

logger = structlog.get_logger()

# Usage with context
log = logger.bind(service="etl-pipeline", environment="production")

def process_order(order_id: str, user_id: str):
    order_log = log.bind(order_id=order_id, user_id=user_id)

    order_log.info("processing_started")

    try:
        # Process...
        order_log.info("processing_completed", duration_ms=150)
    except Exception as e:
        order_log.error("processing_failed", error=str(e), exc_info=True)
        raise
```

## Tools & Technologies

| Tool | Purpose | Version (2025) |
|------|---------|----------------|
| **Prometheus** | Metrics collection | 2.50+ |
| **Grafana** | Visualization | 10.3+ |
| **Loki** | Log aggregation | 2.9+ |
| **Alertmanager** | Alert routing | 0.27+ |
| **Tempo** | Distributed tracing | 1.5+ |
| **OpenTelemetry** | Tracing standard | 1.24+ |
| **node_exporter** | Host metrics | Latest |
| **cAdvisor** | Container metrics | Latest |

## Troubleshooting

### Issue: Targets Not Discovered
**Problem**: Prometheus not scraping targets
**Solution**: Check network connectivity, verify target labels, review service discovery config

### Issue: High Memory Usage
**Problem**: Prometheus using excessive memory
**Solution**: Reduce retention, use recording rules, limit cardinality

### Issue: Slow Queries
**Problem**: PromQL queries timing out
**Solution**: Use recording rules, limit time ranges, optimize queries

### Issue: Missing Data Points
**Problem**: Gaps in metrics data
**Solution**: Check scrape interval, verify target availability

### Issue: Alert Fatigue
**Problem**: Too many alerts
**Solution**: Tune thresholds, add for duration, implement alert grouping

## Best Practices

```python
# ✅ DO: Use appropriate metric types
# Counter for totals, Histogram for latency, Gauge for current values

# ✅ DO: Add meaningful labels (but limit cardinality)
REQUESTS.labels(method='GET', status='200', endpoint='/api').inc()

# ✅ DO: Include correlation IDs in logs
logger.info("request_completed", request_id=request_id)

# ✅ DO: Set up dashboards for key metrics

# ✅ DO: Use recording rules for frequently-used queries

# ✅ DO: Implement proper alerting thresholds

# ❌ DON'T: High cardinality labels (user_id, request_id as labels)
# ❌ DON'T: Log sensitive data
# ❌ DON'T: Alert on every error
# ❌ DON'T Use very short scrape intervals unnecessarily
```

## Resources

- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Tutorials](https://grafana.com/tutorials/)
- [OpenTelemetry](https://opentelemetry.io/)
- [Observability Best Practices](https://www.oreilly.com/library/view/observability-engineering/9781492076726/)

---

## Related Skills

- `kubernetes` - For Kubernetes deployment and monitoring
- `infrastructure-monitoring` - Infrastructure-specific monitoring patterns
- `prometheus-grafana` - (DEPRECATED - merged into this skill)
- `security-best-practices` - Security monitoring considerations
- `devops-automation` - CI/CD pipeline monitoring

---

**Skill Certification Checklist:**
- [ ] Can instrument applications with Prometheus metrics
- [ ] Can create Grafana dashboards
- [ ] Can implement structured logging
- [ ] Can set up alerting rules
- [ ] Can configure Alertmanager routing
- [ ] Can write PromQL queries
- [ ] Can troubleshoot observability issues
- [ ] Can design monitoring architecture
- [ ] Can set up Kubernetes monitoring
