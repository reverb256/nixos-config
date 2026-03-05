# AI Inference Health Monitoring & Model Evaluation

## Overview

This document describes the health monitoring, model evaluation, and metrics tracking system for your AI inference gateway.

**Date**: 2026-03-05
**Gateway**: http://127.0.0.1:8080
**Monitoring Port**: 9190 (Prometheus metrics)
**Grafana**: http://127.0.0.1:3001

---

## Current State

### ✅ What's Working

**Prometheus**:
- ✅ Running and scraping metrics
- ✅ Scraping "ai-inference-zephyr" job
- ✅ URL: http://127.0.0.1:9090

**Grafana**:
- ✅ Running on port 3001
- ✅ 2 dashboards exist
- ✅ Can view Prometheus data

**Metrics Endpoint**:
- ✅ Gateway exports metrics on port 9190
- ✅ Monitor service exports GPU metrics
- ✅ URL: http://127.0.0.1:9190/metrics

### ✅ Fully Implemented

**Gateway Metrics** (NEW):
- ✅ **Request count per model** - `gateway_model_requests_total{model, backend, status}`
- ✅ **Token tracking per model** - Input/output/total tokens
- ✅ **Latency tracking per model** - Request duration with percentiles (p50, p95, p99)
- ✅ **Error rate tracking** - Per-model error rates by error type
- ✅ **Tokens/sec tracking** - Real-time throughput per model
- ✅ **Active requests** - Current concurrent requests per model
- ✅ **Time to first token** - TTFT metrics for streaming
- ✅ **Routing metrics** - Routing decisions, confidence, overrides
- ✅ **Model health scores** - Health, performance, quality scores (0-100)
- ✅ **Context utilization** - Context window usage percentage
- ✅ **Backend metrics** - Per-backend health, latency, errors

**Model Evaluation**:
- ✅ Automated model testing script implemented
- ✅ Quality scoring (arithmetic, reasoning, coding tests)
- ✅ Performance benchmarking (tokens/sec, latency)

**Grafana Dashboard**:
- ✅ Basic dashboard: `ai-inference-dashboard-comprehensive.json`
- ✅ **NEW Comprehensive dashboard**: `ai-inference-dashboard-comprehensive-v2.json`

---

## Components Created

### 1. Model Health Evaluator Script

**File**: `/etc/nixos/scripts/model-health-evaluator.py`

**Features**:
- Tests all models automatically
- Measures tokens/sec and latency
- Evaluates quality across 5 test categories:
  - Simple arithmetic
  - Reasoning
  - Code generation
  - Creative writing
  - Memory/context
- Calculates health scores (0-100)
- Saves results to `/var/lib/ai-inference/evaluations/`

**Usage**:
```bash
# Run full evaluation
python3 /etc/nixos/scripts/model-health-evaluator.py

# Results saved to:
# /var/lib/ai-inference/evaluations/evaluation_YYYYMMDD_HHMMSS.json
# /var/lib/ai-inference/evaluations/latest_evaluation.json
```

**What it evaluates**:
```python
{
  "model": "qwen/qwen3.5-9b",
  "timestamp": "2026-03-05T16:00:00",
  "healthy": true,
  "latency_ms": 1500,
  "tokens_per_second": 45.2,
  "performance_score": 90.4,  # 0-100
  "quality_score": 85.0,      # 0-100
  "overall_score": 87.7       # 0-100
}
```

### 2. Grafana Dashboard Configuration

**File**: `/etc/nixos/modules/services/monitoring/ai-inference-dashboard-comprehensive.json`

**Panels**:
1. GPU Utilization (3060 Ti + 3090)
2. GPU Memory Usage (VRAM used/total)
3. Backend Health Status
4. Backend Request Latency
5. Models Loaded (pie chart)
6. Model Status Table

**To import**:
```bash
# Via Grafana UI:
1. Open http://127.0.0.1:3001
2. Login (admin:cluster-admin)
3. Go to Dashboards → Import
4. Upload: /etc/nixos/modules/services/monitoring/ai-inference-dashboard-comprehensive.json
5. Set UID: ai-inference-model-health
6. Click Import

# Or use API (need correct credentials):
curl -X POST http://127.0.0.1:3001/api/dashboards/db \
  -u admin:YOUR_PASSWORD \
  -H "Content-Type: application/json" \
  -d @/etc/nixos/modules/services/monitoring/ai-inference-dashboard-comprehensive.json
```

### 3. Health Monitoring Script

**File**: `/etc/nixos/scripts/ensure-opencode-gateway.sh`

**Features**:
- Checks gateway health
- Checks LM Studio backend
- Tests inference endpoint
- Lists available models
- Auto-repair on failure

**Usage**:
```bash
# Check health
/etc/nixos/scripts/ensure-opencode-gateway.sh check

# Auto-repair
/etc/nixos/scripts/ensure-opencode-gateway.sh repair

# Continuous monitoring
/etc/nixos/scripts/ensure-opencode-gateway.sh watch
```

---

## Current Metrics Available

### From Monitor Service (port 9190)

**GPU Metrics**:
```
ai_inference_gpu_vram_used_mb{gpu_id="0"}
ai_inference_gpu_vram_total_mb{gpu_id="0"}
ai_inference_gpu_utilization_percent{gpu_id="0"}
ai_inference_gpu_temperature_c{gpu_id="0"}
ai_inference_gpu_power_draw_w{gpu_id="0"}
```

**Backend Metrics**:
```
ai_inference_backend_healthy  # 0 or 1
ai_inference_backend_latency_seconds  # Histogram
ai_inference_backend_latency_seconds_bucket{le="0.5"}
ai_inference_backend_latency_seconds_count
ai_inference_backend_latency_seconds_sum
```

**Model Metrics**:
```
ai_inference_model_loaded{model="qwen/qwen3.5-9b"}  # 0 or 1
```

### ✅ NOW IMPLEMENTED: Per-Model Gateway Metrics

**All metrics below are NOW TRACKED** via the new metrics module:

**Request Metrics**:
```
gateway_model_requests_total{model="qwen/qwen3.5-9b", backend="lm-studio", status="success"}
gateway_model_active_requests{model="qwen/qwen3.5-9b", backend="lm-studio"}
```

**Token Usage Metrics**:
```
gateway_model_tokens_input_total{model="qwen/qwen3.5-9b", backend="lm-studio"}
gateway_model_tokens_output_total{model="qwen/qwen3.5-9b", backend="lm-studio"}
gateway_model_tokens_total{model="qwen/qwen3.5-9b", backend="lm-studio", token_type="input|output"}
gateway_model_tokens_per_second{model="qwen/qwen3.5-9b", backend="lm-studio"}
```

**Latency Metrics**:
```
gateway_model_request_duration_seconds{model="qwen/qwen3.5-9b", backend="lm-studio", le="0.5"}
# Query percentiles:
histogram_quantile(0.95, rate(gateway_model_request_duration_seconds_bucket[5m]))
```

**Time To First Token**:
```
gateway_model_time_to_first_token_seconds{model="qwen/qwen3.5-9b", backend="lm-studio", le="1.0"}
```

**Error Metrics**:
```
gateway_model_errors_total{model="qwen/qwen3.5-9b", backend="lm-studio", error_type="backend_error|unexpected_error"}
gateway_model_error_rate{model="qwen/qwen3.5-9b", backend="lm-studio"}
```

**Routing Metrics**:
```
gateway_routing_requests_total{requested_model="default", selected_model="qwen/qwen3.5-9b", backend="lm-studio"}
gateway_routing_confidence{reason="token_count", specialization="none", le="0.8"}
gateway_routing_overrides_total{requested_model="specific", selected_model="qwen/qwen3.5-9b"}
gateway_routing_specialization_usage{specialization="coding", model="qwen/qwen3.5-9b"}
```

**Model Health Scores** (updated by model evaluator):
```
gateway_model_loaded{model="qwen/qwen3.5-9b"}
gateway_model_health_score{model="qwen/qwen3.5-9b"}  # 0-100
gateway_model_performance_score{model="qwen/qwen3.5-9b"}  # 0-100
gateway_model_quality_score{model="qwen/qwen3.5-9b"}  # 0-100
```

**Context Window Metrics**:
```
gateway_context_utilization_percent{model="qwen/qwen3.5-9b"}
gateway_context_window_used_tokens{model="qwen/qwen3.5-9b", le="32768"}
```

**Backend Metrics**:
```
gateway_backend_requests_total{backend="lm-studio", status="success"}
gateway_backend_errors_total{backend="lm-studio", error_type="timeout"}
gateway_backend_latency_seconds{backend="lm-studio", le="1.0"}
gateway_backend_healthy{backend="lm-studio"}
```

---

## How Per-Model Metrics Work

### Architecture

The gateway now tracks comprehensive metrics through the `ModelMetricsTracker` class:

**File**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/metrics.py`

**Key Components**:

1. **ModelMetricsTracker Class**: Context manager that tracks a single request from start to finish
2. **Automatic Tracking**: Integrated into chat completions endpoint
3. **Streaming Support**: Tracks metrics for both streaming and non-streaming requests
4. **Error Handling**: Records errors with categorization (backend_error, unexpected_error, etc.)

**Request Flow**:
```
1. User sends request → /v1/chat/completions
2. Router selects model → RouteDecision
3. Create ModelMetricsTracker(model, backend, requested_model)
4. Record routing decision (confidence, reason, specialization)
5. Forward to backend (streaming or non-streaming)
6. On success: record tokens, latency, throughput
7. On error: record error type
8. Context manager auto-cleanup: decrement active requests
```

**Example Usage in Gateway**:
```python
# In chat_completions endpoint (main.py)
metrics_tracker = ModelMetricsTracker(
    model=route_decision.model,
    backend=route_decision.backend,
    requested_model=requested_model
)

# Record routing metadata
metrics_tracker.record_routing_decision(
    confidence=0.95,
    reason="token_count",
    specialization="coding"
)

try:
    # Process request...
    response = await openai_client.chat_completion(...)

    # Record success
    metrics_tracker.record_success(
        input_tokens=100,
        output_tokens=200,
        total_tokens=300,
        latency_ms=1500
    )
except Exception as e:
    # Record error
    metrics_tracker.record_error("backend_error")
```

**Metrics Available**:

1. **Request Metrics**
   - Total requests per model (by status: success, error, timeout)
   - Active requests gauge (increment on start, decrement on end)

2. **Token Metrics**
   - Input tokens counter
   - Output tokens counter
   - Total tokens (with token_type label)
   - Tokens per second gauge (updated on each request)

3. **Latency Metrics**
   - Request duration histogram (buckets: 0.1s to 600s)
   - Time to first token histogram (buckets: 0.1s to 30s)

4. **Error Metrics**
   - Error counter (by error_type: timeout, rate_limit, backend_error, etc.)
   - Error rate gauge (calculated as rolling percentage)

5. **Routing Metrics**
   - Routing decisions counter (requested vs selected model)
   - Routing confidence histogram
   - Routing overrides (user explicitly requested model)
   - Specialization usage counter

6. **Health Metrics**
   - Model loaded gauge (updated when /v1/models is called)
   - Model health score (0-100, from evaluation)
   - Model performance score (0-100)
   - Model quality score (0-100)

7. **Context Metrics**
   - Context utilization percentage (tokens / max_context * 100)
   - Context window used histogram

**Querying Metrics**:

```bash
# Get request rate per model
curl -s 'http://127.0.0.1:9090/api/v1/query?query=rate(gateway_model_requests_total[5m])' | jq .

# Get p95 latency per model
curl -s 'http://127.0.0.1:9090/api/v1/query?query=histogram_quantile(0.95, rate(gateway_model_request_duration_seconds_bucket[5m]))' | jq .

# Get current tokens/sec per model
curl -s 'http://127.0.0.1:9090/api/v1/query?query=gateway_model_tokens_per_second' | jq .

# Get error rate per model
curl -s 'http://127.0.0.1:9090/api/v1/query?query=gateway_model_error_rate' | jq .
```

---

## Prometheus Configuration

### Current Scrape Config

**File**: (in your NixOS prometheus config)

```prometheus
scrape_configs:
  - job_name: 'ai-inference-zephyr'
    static_configs:
      - targets: ['127.0.0.1:9190']
    scrape_interval: 15s
```

This is already configured and working! ✅

### Verification

```bash
# Check Prometheus is scraping
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "ai-inference-zephyr")'

# Query metrics
curl -s http://127.0.0.1:9090/api/v1/query?query=ai_inference_backend_healthy | jq .

# Check all AI inference metrics
curl -s http://127.0.0.1:9190/metrics | grep ai_inference
```

---

## Model Evaluation Guide

### Running Full Evaluation

```bash
# Test all models (takes 5-10 minutes)
python3 /etc/nixos/scripts/model-health-evaluator.py

# Output summary:
# - Total models: 20
# - Healthy: 18 (90%)
# - Performance scores
# - Quality scores
# - Best models by category
```

### Evaluation Categories

**1. Simple Arithmetic** (fast, basic functionality)
- Prompt: "What is 2+2?"
- Expected: "4"
- Tests: Basic reasoning, response format

**2. Reasoning** (multi-step logic)
- Prompt: "If I have 5 apples and eat 2, then buy 3 more..."
- Expected: "6"
- Tests: Multi-step reasoning, number tracking

**3. Code Generation** (programming capability)
- Prompt: "Write a Python function to check if a number is prime."
- Tests: Code quality, syntax, logic

**4. Creative Writing** (natural language)
- Prompt: "Write a haiku about AI."
- Tests: Creativity, format compliance

**5. Memory/Context** (short-term memory)
- Prompt: "Remember this number: 42. What was the number?"
- Tests: Context window, memory

### Interpreting Results

**Health Score Formula**:
```
Performance Score = (tokens_per_second / 50) * 100
  - 50 tok/sec = 100% (excellent)
  - 25 tok/sec = 50% (good)
  - 10 tok/sec = 20% (poor)

Quality Score = (correct_tests / total_tests) * 100
  - 3/3 correct = 100%
  - 2/3 correct = 67%
  - 1/3 correct = 33%

Overall Score = (Performance + Quality) / 2
```

**Score Guidelines**:
- 90-100: Excellent (production-ready)
- 70-89: Good (usable)
- 50-69: Fair (use with caution)
- <50: Poor (needs attention)

---

## Setting Up Grafana Dashboards

You have **TWO dashboards** available:

### Dashboard 1: Basic Model Health (Original)

**File**: `/etc/nixos/modules/services/monitoring/ai-inference-dashboard-comprehensive.json`
**UID**: `ai-inference-model-health`

**Panels**:
- GPU Utilization (3060 Ti + 3090)
- GPU Memory Usage (VRAM used/total)
- Backend Health Status
- Backend Request Latency
- Models Loaded (pie chart)
- Model Status Table

### Dashboard 2: Comprehensive Metrics & Monitoring (NEW)

**File**: `/etc/nixos/modules/services/monitoring/ai-inference-dashboard-comprehensive-v2.json`
**UID**: `ai-inference-comprehensive-v2`

**Panels** (18 panels across 7 sections):

**GPU & Infrastructure Metrics**:
- GPU Utilization (per GPU with stats)
- GPU Memory Usage (used/total per GPU)

**Model Request Metrics**:
- Request Rate (per model, requests/sec)
- Active Requests (current concurrent requests per model)
- Token Throughput (input/output tokens/sec)
- Tokens Per Second (per model gauge)

**Latency & Performance Metrics**:
- Request Latency (p50, p95, p99 percentiles)
- Time To First Token (TTFT - p95)

**Error & Reliability Metrics**:
- Error Rate (per model, percentage)
- Errors By Type (pie chart)

**Routing & Model Selection Metrics**:
- Routing Decisions (pie chart by selected model)
- Routing Overrides (user-requested specific models)
- Routing Confidence Score (p95 by reason/specialization)

**Model Health & Quality Scores**:
- Model Loaded Status (table)
- Model Health Scores (health, performance, quality from evaluation)
- Context Window Utilization % (per model)

**Backend Health & Performance**:
- Backend Health Status (status indicators)
- Backend Latency (p95 per backend)
- Backend Request Distribution (pie chart)

### Import Instructions

**Option 1: Import via UI**

1. Open Grafana: http://127.0.0.1:3001
2. Login with credentials
3. Navigate to: Dashboards → Import
4. Upload either dashboard file:
   - Basic: `ai-inference-dashboard-comprehensive.json`
   - Comprehensive: `ai-inference-dashboard-comprehensive-v2.json`
5. Set appropriate UID
6. Click: Import

**Option 2: Via API**

```bash
# Find your Grafana credentials first
cat /var/lib/grafana/admin-password

# Import comprehensive dashboard (recommended)
DASHBOARD_FILE="/etc/nixos/modules/services/monitoring/ai-inference-dashboard-comprehensive-v2.json"

curl -X POST http://127.0.0.1:3001/api/dashboards/db \
  -u admin:$(cat /var/lib/grafana/admin-password) \
  -H "Content-Type: application/json" \
  -d "{
    \"dashboard\": $(cat $DASHBOARD_FILE),
    \"overwrite\": true,
    \"message\": \"AI Inference Comprehensive Metrics\"
  }"
```

### Dashboard Features

Once imported, the dashboard provides:

**Real-time Metrics** (10s refresh):
- GPU utilization per GPU (3060 Ti, 3090)
- GPU memory usage (used/total)
- Backend health status
- Request latency (p50, p95, p99)
- Model availability (pie chart)
- Model status table

**Historical Analysis**:
- Time-series graphs for all metrics
- Identify performance trends
- Detect anomalies
- Compare models

---

## ✅ Complete Coverage Achieved

### 1. ✅ Gateway Metrics Enhancement - FULLY IMPLEMENTED

**Status**: ✅ Complete

**Implementation**: `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/metrics.py` + integrated into `main.py`

**All requested metrics are NOW TRACKED**:
- ✅ Request count per model
- ✅ Token usage per model (input, output, total)
- ✅ Request duration per model (histogram with percentiles)
- ✅ Error rate per model (by error type)
- ✅ Active connections per model
- ✅ Tokens per second per model
- ✅ Time to first token per model
- ✅ Routing decisions and confidence
- ✅ Model health scores
- ✅ Context window utilization

**Key Features**:
- Context manager auto-cleanup
- Streaming and non-streaming support
- Error categorization
- Automatic model availability updates
    'Active connections per model',
    ['model']
)

# In your chat completions endpoint:
model_requests.labels(model=model_id).inc()
model_tokens_input.labels(model=model_id).inc(usage.prompt_tokens)
model_tokens_output.labels(model=model_id).inc(usage.completion_tokens)
model_duration.labels(model=model_id).observe(latency)
```

### 2. Automated Health Checks

Add to crontab or systemd timer:

```bash
# Run evaluation every hour
0 * * * * python3 /etc/nixos/scripts/model-health-evaluator.py

# Or use systemd timer
systemctl enable opencode-gateway-health.timer
systemctl start opencode-gateway-health.timer
```

### 3. Alerting

Configure Prometheus alerts:

```yaml
groups:
  - name: ai_inference
    rules:
      - alert: ModelUnhealthy
        expr: ai_inference_model_loaded < 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Model {{ $model }} is not loaded"

      - alert: HighErrorRate
        expr: rate(gateway_model_errors_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate for {{ $model }}"

      - alert: SlowResponse
        expr: histogram_quantile(0.95, rate(gateway_model_request_duration_seconds_bucket[5m])) > 30
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Slow responses from {{ $model }}"
```

---

## Quick Start Commands

### Check Current Status

```bash
# Check gateway health
curl -s http://127.0.0.1:8080/health | jq .

# Check metrics endpoint
curl -s http://127.0.0.1:9190/metrics | grep ai_inference | head -20

# Check Prometheus targets
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "ai-inference-zephyr")'

# List models
curl -s http://127.0.0.1:8080/v1/models | jq -r '.data[].id' | wc -l
```

### Run Evaluation

```bash
# Full model evaluation
python3 /etc/nixos/scripts/model-health-evaluator.py

# View latest results
cat /var/lib/ai-inference/evaluations/latest_evaluation.json | jq .

# Run health check
/etc/nixos/scripts/ensure-opencode-gateway.sh check
```

### View Metrics

```bash
# In Prometheus UI
# Open: http://127.0.0.1:9090

# Check all gateway metrics
curl -s http://127.0.0.1:9190/metrics | grep gateway_

# Per-model request rate
curl -s 'http://127.0.0.1:9090/api/v1/query?query=rate(gateway_model_requests_total[5m])' | jq .

# Per-model tokens/sec
curl -s 'http://127.0.0.1:9090/api/v1/query?query=gateway_model_tokens_per_second' | jq .

# Per-model p95 latency
curl -s 'http://127.0.0.1:9090/api/v1/query?query=histogram_quantile(0.95, rate(gateway_model_request_duration_seconds_bucket[5m]))' | jq .

# Error rate per model
curl -s 'http://127.0.0.1:9090/api/v1/query?query=gateway_model_error_rate' | jq .

# Active requests per model
curl -s 'http://127.0.0.1:9090/api/v1/query?query=gateway_model_active_requests' | jq .

# Routing decisions
curl -s 'http://127.0.0.1:9090/api/v1/query?query=gateway_routing_requests_total' | jq .

# In Grafana UI
# Open: http://127.0.0.1:3001
# Navigate to Dashboards
# Two dashboards available:
#  - AI Inference - Model Health & Performance (basic)
#  - AI Inference - Comprehensive Metrics & Monitoring (full featured)
```

---

## Summary

### ✅ Currently Working

1. **Prometheus**: Scraping metrics from port 9190
2. **Grafana**: Running on port 3001
3. **GPU Metrics**: Utilization, memory, temperature, power
4. **Backend Health**: Basic health status
5. **Backend Latency**: Histogram of request times
6. **Model Status**: Which models are loaded

### ✅ Created Today

1. **Model Health Evaluator**: Comprehensive testing script
2. **Health Monitoring Script**: Gateway checks + auto-repair
3. **Grafana Dashboard Config**: Ready to import
4. **Documentation**: Complete monitoring guide

### ✅ Fully Implemented (Latest Session)

**Per-Model Metrics Module** (`metrics.py`):
- Request count per model (with status labels)
- Token tracking (input, output, total)
- Request duration with percentiles (p50, p95, p99)
- Error tracking by type
- Tokens per second gauge
- Active requests gauge
- Time to first token (TTFT)
- Context window utilization

**Routing Metrics**:
- Routing decisions counter
- Routing confidence histogram
- Routing overrides (user-specified models)
- Specialization usage tracking

**Model Health Scores**:
- Model loaded status
- Health score (0-100)
- Performance score (0-100)
- Quality score (0-100)

**Integrated into Gateway**:
- Chat completions endpoint tracking
- Streaming and non-streaming support
- Automatic error categorization
- Model availability updates

**Comprehensive Grafana Dashboard**:
- 18 panels across 7 sections
- All per-model metrics visualized
- Real-time 10s refresh
- Historical analysis capabilities

### 🎯 Optional Enhancements

1. **Dashboard Import**: Import comprehensive dashboard via UI or API
2. **Systemd Timer**: Set up automated health checks (hourly/daily)
3. **Prometheus Alerts**: Configure alerting rules for critical issues

---

## Files Created/Modified

**New Files (Latest Session)**:
- `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/metrics.py` (619 lines)
  - Comprehensive per-model metrics module
  - ModelMetricsTracker class for request lifecycle tracking
  - RoutingMetricsTracker class for routing decisions
  - All Prometheus metric definitions

- `/etc/nixos/modules/services/monitoring/ai-inference-dashboard-comprehensive-v2.json`
  - Comprehensive Grafana dashboard with all per-model metrics
  - 18 panels across 7 sections
  - Real-time monitoring and historical analysis

**Modified Files**:
- `/etc/nixos/modules/services/ai-inference/ai_inference_gateway/main.py`
  - Integrated ModelMetricsTracker into chat completions endpoint
  - Added metrics module import
  - Updated streaming handler (stream_backend_response)
  - Updated non-streaming handler (handle_non_streaming_request)
  - Model availability tracking in /v1/models endpoint

- `/etc/nixos/docs/ai-inference-monitoring.md`
  - Updated with all new metrics documentation
  - Added metrics architecture explanation
  - Query examples for all new metrics
  - Both dashboards documented

**Previously Created Files**:
- `/etc/nixos/scripts/model-health-evaluator.py` (460 lines)
- `/etc/nixos/scripts/setup-grafana-dashboard.sh`
- `/etc/nixos/modules/services/monitoring/ai-inference-dashboard-comprehensive.json` (basic)

---

## Immediate Actions You Can Take

1. **Test the evaluator**:
   ```bash
   python3 /etc/nixos/scripts/model-health-evaluator.py
   ```

2. **Check new metrics**:
   ```bash
   curl -s http://127.0.0.1:9190/metrics | grep gateway_model | head -30
   ```

3. **Query specific metrics**:
   ```bash
   # Request rate per model
   curl -s 'http://127.0.0.1:9090/api/v1/query?query=rate(gateway_model_requests_total[5m])' | jq .

   # Tokens per second
   curl -s 'http://127.0.0.1:9090/api/v1/query?query=gateway_model_tokens_per_second' | jq .

   # P95 latency per model
   curl -s 'http://127.0.0.1:9090/api/v1/query?query=histogram_quantile(0.95, rate(gateway_model_request_duration_seconds_bucket[5m]))' | jq .

   # Error rate per model
   curl -s 'http://127.0.0.1:9090/api/v1/query?query=gateway_model_error_rate' | jq .
   ```

4. **Import comprehensive dashboard** (optional):
   - Open http://127.0.0.1:3001
   - Dashboards → Import
   - Upload: `ai-inference-dashboard-comprehensive-v2.json`

This gives you **comprehensive model comparison and selection capabilities**!
