---
name: monitoring
description: >
  Comprehensive monitoring, dashboards, and observability expertise. Covers Grafana dashboard creation,
  Prometheus configuration, monitoring architecture, alerting, and observability best practices.
  Use for setting up monitoring, creating dashboards, configuring Prometheus, or building observability stacks.
risk: low
version: 1.0.0
---

# Monitoring & Observability

Expert guidance for monitoring systems, creating dashboards, and building observability stacks.

## When to Use

- **Dashboard Creation**: Building Grafana dashboards for metrics visualization
- **Prometheus Setup**: Configuring Prometheus for metrics collection
- **Monitoring Architecture**: Designing monitoring strategies and architectures
- **Observability**: Setting up logs, metrics, and tracing
- **Alerting**: Configuring alerts and alert routing
- **LLM Monitoring**: Specific monitoring for LLM applications and inference

## Monitoring Architecture

### The Three Pillars of Observability

```
┌─────────────────────────────────────────────────────────────┐
│                      OBSERVABILITY                        │
├──────────────┬──────────────┬──────────────┬──────────────┤
│   METRICS    │     LOGS      │    TRACES     │     EVENTS    │
│ (Prometheus)  │   (Loki)     │   (Tempo/Jeager) │  (User/Action) │
├──────────────┴──────────────┴──────────────┴──────────────┤
│                    GRAFANA                             │
│               (Visualization & Alerting)                      │
└────────────────────────────────────────────────────────────┘
```

### Metric Types

| Type | Purpose | Example |
|------|---------|---------|
| **RED** | Rate | Requests per second |
| **Latency** | Duration | P95, P99 response time |
| **Errors** | Count | Error rate, 5xx percentage |
| **Saturation** | Resource | CPU, memory, disk usage |

## Prometheus Configuration

### Key Concepts

**Scrape Configuration**:
```yaml
scrape_configs:
  - job_name: 'api'
    static_configs:
      - targets: ['localhost:8080']
    scrape_interval: 15s
    metrics_path: /metrics
```

**Histogram for Latency**:
```python
from prometheus_client import Histogram

request_duration = Histogram(
    'http_request_duration_seconds',
    'API request duration',
    buckets=[0.1, 0.5, 1, 2, 5, 10, 30, 60, 300]
)
```

**Counter for Events**:
```python
from prometheus_client import Counter

requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)
```

### Best Practices

1. **Use appropriate metric types**
   - Counter: Events that only increase (requests, errors)
   - Gauge: Values that go up and down (memory, connections)
   - Histogram: Distributions (latency, request sizes)
   - Summary: Pre-calculated quantiles

2. **Label strategically**
   - Include relevant dimensions: endpoint, method, status
   - Avoid high cardinality labels: user_id, request_id
   - Use consistent label names across metrics

3. **Set appropriate buckets**
   - For latency: exponential buckets (1ms, 10ms, 100ms, 1s, 10s)
   - For sizes: powers of 2 (1KB, 2KB, 4KB, 8KB...)

4. **Scrape targets efficiently**
   - Set appropriate scrape intervals (15s for critical, 1m for others)
   - Use relabeling to standardize metrics
   - Filter unnecessary metrics with metric_relabel_configs

## Grafana Dashboards

See separate `grafana-dashboards` skill for comprehensive dashboard creation guidance.

### Dashboard Organization

1. **Overview Dashboards**: High-level system health
2. **Service Dashboards**: Per-service metrics
3. **Resource Dashboards**: CPU, memory, disk, network
4. **Business Dashboards**: User-facing KPIs

### Alerting in Grafana

**Alert Rule**:
```json
{
  "conditions": [
    {
      "evaluator": {"params": [5], "type": "gt"},
      "operator": {"type": "and"},
      "query": {"params": ["A", "5m", "now"]}
    }
  ],
  "for": "5m",
  "annotations": {
    "summary": "High error rate detected",
    "runbook": "https://wiki.company.com/runbooks/alert-123"
  }
}
```

## LLM & AI Monitoring

### LLM-Specific Metrics

| Metric | Description |
|--------|-------------|
| Request rate | Tokens/second generated |
| Latency | Time to first token, total generation time |
| Token counts | Input tokens, output tokens, total |
| Model usage | Which model, version, provider |
| Error rate | Failed requests, timeouts |
| Cost tracking | Estimated cost per request |

### LLM Dashboard Panels

1. **Request Rate**: RPS, tokens/second by model
2. **Latency**: P50, P95, P99 generation time
3. **Token Throughput**: Input/output token ratios
4. **Model Distribution**: Requests per model
5. **Error Tracking**: Failure rate by model/error type
6. **Cost Metrics**: Estimated cost per 1K tokens

### Example Queries

```promql
# Token generation rate
sum(rate(llm_tokens_generated_total[5m])) by (model)

# P95 latency
histogram_quantile(0.95, sum(rate(llm_generation_duration_seconds_bucket[5m])) by (le, model))

# Error rate
(sum(rate(llm_requests_total{status="error"}[5m])) / sum(rate(llm_requests_total[5m]))) * 100
```

## Alert Design

### Alert Principles

1. **Actionable**: Each alert should suggest a remediation
2. **Specific**: Include relevant context (hostname, service, endpoint)
3. **Threshold-based**: Set appropriate thresholds to avoid alert fatigue
4. **Hierarchical**: Critical alerts page to less critical ones
5. **Runbook links**: Include documentation for common issues

### Alert Routing

```
Critical → PagerDuty → On-call engineer (SMS + call)
High      → Slack #alerts → Team channel
Medium    → Email → Daily digest
Low       → Aggregate → Weekly report
```

## Observability Strategy

### Monitoring Maturity Levels

| Level | Capability |
|-------|------------|
| **Basic** | Up/down checks, basic metrics |
| **Enhanced** | Application metrics, structured logging |
| **Advanced** | Distributed tracing, SLO/SLI tracking |
| **Optimal** | ML-based anomaly detection, predictive alerting |

### Implementation Priority

1. **Foundation** (Weeks 1-4)
   - Install exporters (Node, Postgres, NGINX)
   - Set up Prometheus and Grafana
   - Create basic dashboards

2. **Application** (Weeks 5-8)
   - Add application metrics
   - Implement structured logging
   - Create service-specific dashboards

3. **Correlation** (Weeks 9-12)
   - Add distributed tracing
   - Create cross-service dashboards
   - Implement SLO/SLI tracking

4. **Intelligence** (Ongoing)
   - Anomaly detection
   - Predictive alerting
   - Automated remediation

## Common Patterns

### RED Method (Services)

Monitor and alert on:
- **R**ate: Requests per second dropping
- **E**rrors: Error rate increasing
- **D**uration: Response time increasing

### USE Method (Resources)

Monitor and alert on:
- **U**tilization: CPU > 80%
- **S**aturation: Queue length increasing
- **E**rrors: Error rate increasing

### Golden Signals (Google)

| Signal | Description |
|--------|-------------|
| **Latency** | Service responsiveness |
| **Traffic** | Request volume |
| **Errors** | Failed requests |
| **Saturation** | Resource utilization |

## Quick Reference

### Exporter Selection

| Resource | Exporter | Port |
|----------|----------|-----|
| Node exporter | prom/node-exporter | 9100 |
| cAdvisor | google/cadvisor | 8080 |
| StatsD exporter | prom/statsd-exporter | 9102 |
| Postgres exporter | prometheuscommunity/postgres-exporter | 9187 |
| NGINX exporter | prometheuscommunity/nginx-exporter | 9113 |
| Redis exporter | oliver006/redis_exporter | 9121 |

### Target Configuration

```yaml
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
```

## Related Skills

- `grafana-dashboards` - Dashboard creation
- `prometheus-configuration` - Prometheus setup
- `building-dashboards` - Dashboard architecture
- `llm-monitoring-dashboard` - LLM-specific monitoring
