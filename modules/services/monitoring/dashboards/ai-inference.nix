# AI Inference Gateway Dashboard
# Monitoring for the AI inference gateway - latency, throughput, errors
{lib, ...}: let
  inherit (lib.dashboard) panels template grid thresholds;
in {
  aiInference = template {
    title = "🤖 AI Inference Gateway";
    description = "Real-time AI inference metrics including latency, throughput, and error rates";
    tags = ["ai" "inference" "llm" "gateway"];
    panels = [
      # ========== ROW: GATEWAY STATUS ==========
      (panels.row "🚪 Gateway Status" false)
      # Backend Health
      (panels.stat {
        title = "Backend Health";
        expr = "ai_inference_backend_healthy";
        gridPos = {h = 4; w = 6; x = 0; y = 1;};
        thresholds = thresholds.binary;
        colorMode = "background";
      })
      # Active Requests
      (panels.stat {
        title = "Active Requests";
        expr = "gateway_active_requests";
        gridPos = {h = 4; w = 6; x = 6; y = 1;};
        thresholds = [
          {color = "green"; value = null;}
          {color = "yellow"; value = 5;}
          {color = "orange"; value = 10;}
          {color = "red"; value = 20;}
        ];
        colorMode = "value";
      })
      # Request Rate
      (panels.stat {
        title = "Request Rate";
        expr = "sum(rate(gateway_model_requests_total[5m])) * 60";
        gridPos = {h = 4; w = 6; x = 12; y = 1;};
        unit = "rpm";
        colorMode = "value";
      })
      # Error Rate
      (panels.gauge {
        title = "Error Rate";
        expr = "sum(rate(gateway_model_requests_total{error!=\"none\"}[5m])) / sum(rate(gateway_model_requests_total[5m])) * 100";
        gridPos = {h = 4; w = 6; x = 18; y = 1;};
        thresholds = thresholds.errorRate;
        unit = "percent";
      })

      # ========== ROW: LATENCY ==========
      (panels.row "⏱️ Latency Analysis" false)
      # Request Duration Percentiles
      (panels.timeseries {
        title = "Request Duration Percentiles";
        expr = [
          "histogram_quantile(0.50, sum(rate(gateway_model_request_duration_seconds_bucket[5m])) by (le, model))"
          "histogram_quantile(0.95, sum(rate(gateway_model_request_duration_seconds_bucket[5m])) by (le, model))"
          "histogram_quantile(0.99, sum(rate(gateway_model_request_duration_seconds_bucket[5m])) by (le, model))"
        ];
        gridPos = {h = 10; w = 12; x = 0; y = 5;};
        unit = "s";
        custom = {
          axisCenteredZero = false;
          axisColorMode = "text";
          drawStyle = "line";
          fillOpacity = 10;
          gradientMode = "scheme";
          lineInterpolation = "smooth";
          lineWidth = 2;
          spanNulls = true;
        };
      })
      # Time to First Token
      (panels.timeseries {
        title = "Time to First Token";
        expr = "gateway_model_time_to_first_token_seconds";
        gridPos = {h = 10; w = 12; x = 12; y = 5;};
        unit = "s";
        legendFormat = "{{model}}";
      })

      # ========== ROW: THROUGHPUT ==========
      (panels.row "📊 Throughput Metrics" true)
      # Token Throughput
      (panels.timeseries {
        title = "Token Throughput (Tokens/Sec)";
        expr = "sum(rate(gateway_model_tokens_total[5m]))";
        gridPos = {h = 8; w = 12; x = 0; y = 15;};
        unit = "tps";
        legendFormat = "{{model}}";
      })
      # Input/Output Token Rates
      (panels.timeseries {
        title = "Input vs Output Token Rates";
        expr = [
          "sum(rate(gateway_model_input_tokens_total[5m]))"
          "sum(rate(gateway_model_output_tokens_total[5m]))"
        ];
        gridPos = {h = 8; w = 12; x = 12; y = 15;};
        unit = "tps";
        legendFormat = "{{__name__}}";
      })

      # ========== ROW: MODEL USAGE ==========
      (panels.row "🎯 Model Usage" true)
      # Requests by Model
      (panels.piechart {
        title = "Requests Distribution by Model";
        expr = "sum(gateway_model_requests_total) by (model)";
        gridPos = {h = 10; w = 12; x = 0; y = 23;};
      })
      # Tokens by Model
      (panels.piechart {
        title = "Tokens Distribution by Model";
        expr = "sum(gateway_model_tokens_total) by (model)";
        gridPos = {h = 10; w = 12; x = 12; y = 23;};
      })

      # ========== ROW: ERRORS ==========
      (panels.row "⚠️ Error Analysis" true)
      # Error Rate Over Time
      (panels.timeseries {
        title = "Error Rate Over Time";
        expr = "sum(rate(gateway_model_requests_total{error!=\"none\"}[5m])) / sum(rate(gateway_model_requests_total[5m])) * 100";
        gridPos = {h = 8; w = 12; x = 0; y = 33;};
        thresholds = thresholds.errorRate;
        unit = "percent";
      })
      # Errors by Type
      (panels.piechart {
        title = "Errors by Type";
        expr = "sum(gateway_model_requests_total) by (error)";
        gridPos = {h = 8; w = 12; x = 12; y = 33;};
      })

      # ========== ROW: BACKEND PERFORMANCE ==========
      (panels.row "🔧 Backend Performance" true)
      # Backend Request Duration
      (panels.timeseries {
        title = "Backend Request Duration";
        expr = "histogram_quantile(0.95, sum(rate(gateway_backend_latency_seconds_bucket[5m])) by (le))";
        gridPos = {h = 8; w = 12; x = 0; y = 41;};
        unit = "s";
        legendFormat = "{{backend}}";
      })
      # Backend Request Rate
      (panels.timeseries {
        title = "Backend Request Rate";
        expr = "sum(rate(gateway_backend_requests_total[5m])) by (backend)";
        gridPos = {h = 8; w = 12; x = 12; y = 41;};
        legendFormat = "{{backend}}";
      })

      # ========== ROW: CACHE PERFORMANCE ==========
      (panels.row "💾 Cache Performance (Redis)" true)
      # Cache Hit Rate
      (panels.gauge {
        title = "Cache Hit Rate";
        expr = "redis_cache_hits / (redis_cache_hits + redis_cache_misses) * 100";
        gridPos = {h = 6; w = 12; x = 0; y = 49;};
        thresholds = [
          {color = "red"; value = null;}
          {color = "yellow"; value = 50;}
          {color = "orange"; value = 70;}
          {color = "green"; value = 85;}
        ];
        unit = "percent";
      })
      # Cache Memory Usage
      (panels.gauge {
        title = "Cache Memory Used";
        expr = "redis_memory_used_bytes / redis_memory_max_bytes * 100";
        gridPos = {h = 6; w = 12; x = 12; y = 49;};
        thresholds = thresholds.percentage;
        unit = "percent";
      })
    ];
  };
}
