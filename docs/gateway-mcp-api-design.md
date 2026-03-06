# Gateway MCP Server - Complete API Surface Design

**Phase 1.2**: Complete Tool Specification

## Overview

This document defines the complete API surface for the Gateway MCP Server, including **30+ tools** organized into **6 categories** with full specifications for parameters, return types, permissions, and validation rules.

---

## 📋 Tool Categories

1. **Configuration Management** (7 tools)
2. **Backend Management** (8 tools)
3. **Routing Control** (5 tools)
4. **Cache Management** (7 tools)
5. **Observability & Diagnostics** (6 tools)
6. **Advanced AI Optimization** (5 tools)

---

## 1️⃣ Configuration Management Tools

### **1.1 get_config**

Get current gateway configuration.

**Permission**: `read`

**Parameters**:
```python
{
  "section": Optional[str],  # "routing", "cache", "backends", "logging", or None for all
  "include_overrides": bool = True,  # Include runtime overrides
  "include_defaults": bool = False  # Include default values
}
```

**Returns**:
```json
{
  "routing": {
    "strategy": "weighted",
    "fallback_backend": "zai",
    "weights": {
      "lm-studio": 0.7,
      "zai": 0.3
    }
  },
  "cache": {
    "semantic_ttl": 300,
    "redis_enabled": true
  },
  "backends": {
    "lm-studio": {
      "url": "http://127.0.0.1:1234",
      "enabled": true
    },
    "zai": {
      "url": "https://api.z.ai/api/coding/paas/v4",
      "enabled": true
    }
  }
}
```

**Validation**:
- Section must be one of: "routing", "cache", "backends", "logging"
- If section=None, return all sections

---

### **1.2 update_config**

Update a configuration value (requires validation).

**Permission**: `write`

**Parameters**:
```python
{
  "section": str,  # "routing", "cache", "backends", "logging"
  "key": str,  # Configuration key name
  "value": Any,  # New value
  "validate": bool = True,  # Validate before applying
  "dry_run": bool = False  # Preview change without applying
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Updated routing.weight.lm-studio to 0.8",
  "previous_value": 0.7,
  "new_value": 0.8,
  "change_id": 123,  # For rollback
  "validated": true,
  "warnings": []  # Validation warnings
}
```

**Validation Rules**:
```python
# Routing weights
if section == "routing" and key == "weights":
    if not 0 <= value <= 1:
        raise ValueError("Weight must be between 0 and 1")

# Cache TTL
if section == "cache" and key.endswith("_ttl"):
    if not 60 <= value <= 3600:
        raise ValueError("TTL must be between 60 and 3600 seconds")

# Protected keys
PROTECTED_KEYS = ["api_keys", "backend_urls", "authentication"]
if section in PROTECTED_KEYS:
    require_permission("admin")
```

---

### **1.3 reset_config**

Reset a configuration value to its default.

**Permission**: `write`

**Parameters**:
```python
{
  "section": str,
  "key": Optional[str],  # None to reset entire section
  "confirm": bool = False  # Required for full section reset
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Reset routing.weights to defaults",
  "previous_value": {
    "lm-studio": 0.5,
    "zai": 0.5
  },
  "new_value": {
    "lm-studio": 0.7,
    "zai": 0.3
  }
}
```

---

### **1.4 reload_config**

Reload configuration from file (discards runtime overrides).

**Permission**: `write`

**Parameters**:
```python
{
  "confirm": bool = False  # Required to discard changes
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Configuration reloaded from file",
  "overrides_discarded": 5,
  "backends_reloaded": true
}
```

---

### **1.5 validate_config**

Validate current configuration without applying changes.

**Permission**: `read`

**Parameters**:
```python
{
  "section": Optional[str],  # None for all sections
}
```

**Returns**:
```json
{
  "valid": true,
  "errors": [],
  "warnings": [
    {
      "section": "routing",
      "key": "weights",
      "issue": "Weights don't sum to 1.0",
      "severity": "warning"
    }
  ],
  "recommendations": [
    "Consider adjusting weights for better load distribution"
  ]
}
```

---

### **1.6 get_config_diff**

Show differences between base config and runtime overrides.

**Permission**: `read`

**Parameters**: None

**Returns**:
```json
{
  "overrides": {
    "routing": {
      "weights": {
        "lm-studio": {
          "base": 0.7,
          "override": 0.5,
          "override_time": "2026-03-05T18:00:00Z"
        }
      }
    }
  },
  "summary": {
    "total_overrides": 3,
    "sections_modified": ["routing", "cache"],
    "last_override": "5 minutes ago"
  }
}
```

---

### **1.7 rollback_config**

Rollback a specific configuration change.

**Permission**: `write`

**Parameters**:
```python
{
  "change_id": int,  # Change ID to rollback
  "confirm": bool = False  # Required for safety
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Rolled back change 123",
  "rolled_back_value": {
    "section": "routing",
    "key": "weights",
    "value": {"lm-studio": 0.7}
  },
  "current_value": {
    "section": "routing",
    "key": "weights",
    "value": {"lm-studio": 0.5}
  }
}
```

---

## 2️⃣ Backend Management Tools

### **2.1 list_backends**

List all configured backends with their status.

**Permission**: `read`

**Parameters**: None

**Returns**:
```json
{
  "backends": [
    {
      "name": "lm-studio",
      "type": "lm-studio",
      "url": "http://127.0.0.1:1234",
      "enabled": true,
      "healthy": false,
      "weight": 0.7,
      "priority": 1,
      "metrics": {
        "requests_per_second": 125,
        "avg_latency_ms": 450,
        "error_rate": 0.02,
        "last_error": "Connection refused"
      }
    },
    {
      "name": "zai",
      "type": "zai",
      "url": "https://api.z.ai/api/coding/paas/v4",
      "enabled": true,
      "healthy": true,
      "weight": 0.3,
      "priority": 2,
      "metrics": {
        "requests_per_second": 50,
        "avg_latency_ms": 800,
        "error_rate": 0.005
      }
    }
  ],
  "total_backends": 2,
  "enabled_backends": 2,
  "healthy_backends": 1
}
```

---

### **2.2 get_backend_info**

Get detailed information about a specific backend.

**Permission**: `read`

**Parameters**:
```python
{
  "name": str,  # Backend name
  "include_metrics": bool = True,
  "include_config": bool = True
}
```

**Returns**:
```json
{
  "name": "zai",
  "type": "zai",
  "url": "https://api.z.ai/api/coding/paas/v4",
  "enabled": true,
  "healthy": true,
  "weight": 0.3,
  "priority": 2,
  "config": {
    "api_key_file": "/run/agenix/zai-api-key",
    "timeout": 30.0,
    "max_retries": 3
  },
  "metrics": {
    "requests_per_second": 50,
    "avg_latency_ms": 800,
    "p50_latency_ms": 700,
    "p95_latency_ms": 1200,
    "p99_latency_ms": 2000,
    "error_rate": 0.005,
    "success_rate": 0.995,
    "last_health_check": "2026-03-05T18:25:00Z",
    "uptime_seconds": 86400
  },
  "models": ["glm-4.5", "glm-4.6", "glm-4.7", "glm-5"]
}
```

---

### **2.3 add_backend**

Add a new backend dynamically.

**Permission**: `write`

**Parameters**:
```python
{
  "name": str,  # Backend name (unique)
  "url": str,  # Backend URL
  "type": str,  # "lm-studio", "zai", "kilo", "openai"
  "weight": float = 1.0,  # Routing weight (0-1)
  "priority": int = 10,  # Priority (lower = preferred)
  "api_key_file": Optional[str],  # Path to API key file
  "timeout": float = 30.0,  # Request timeout
  "test_before_enable": bool = True  # Test connectivity before enabling
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Added backend 'kil-ai'",
  "backend": {
    "name": "kil-ai",
    "url": "https://api.kil.ai/v1",
    "type": "kilo",
    "weight": 0.5,
    "enabled": true,
    "healthy": true
  },
  "warnings": [
    "Backend URL has high latency (2000ms), consider weight < 0.3"
  ]
}
```

**Validation**:
```python
# Name uniqueness
if name in gateway_state.backends:
    raise ValueError(f"Backend {name} already exists")

# URL format
if not url.startswith(("http://", "https://")):
    raise ValueError("URL must start with http:// or https://")

# Weight range
if not 0 <= weight <= 1:
    raise ValueError("Weight must be between 0 and 1")

# Type validation
ALLOWED_TYPES = ["lm-studio", "zai", "kilo", "openai"]
if type not in ALLOWED_TYPES:
    raise ValueError(f"Type must be one of: {ALLOWED_TYPES}")

# Test connectivity
if test_before_enable:
    healthy = await test_backend_url(url)
    if not healthy:
        raise ValueError(f"Backend {url} is not healthy")
```

---

### **2.4 remove_backend**

Remove a backend from the gateway.

**Permission**: `admin`

**Parameters**:
```python
{
  "name": str,
  "confirm": bool = False,  # Required confirmation
  "drain_seconds": int = 30  # Grace period before removal
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Backend 'kil-ai' will be removed in 30 seconds",
  "backend": "kil-ai",
  "removal_time": "2026-03-05T18:35:00Z",
  "active_requests": 2  # Requests being drained
}
```

**Safety Checks**:
```python
# Cannot remove last backend
if len(gateway_state.backends) == 1:
    raise ValueError("Cannot remove the last backend")

# Check for active requests
active = count_active_requests(name)
if active > 0 and not confirm:
    return {
        "error": f"Backend has {active} active requests",
        "require_confirmation": True
    }

# Graceful drain
if drain_seconds > 0:
    await drain_backend(name, drain_seconds)
```

---

### **2.5 enable_backend**

Enable a disabled backend.

**Permission**: `write`

**Parameters**:
```python
{
  "name": str,
  "test_first": bool = True  # Test before enabling
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Enabled backend 'lm-studio'",
  "backend": "lm-studio",
  "test_result": {
    "healthy": true,
    "latency_ms": 350
  }
}
```

---

### **2.6 disable_backend**

Disable a backend (stop sending new requests).

**Permission**: `write`

**Parameters**:
```python
{
  "name": str,
  "reason": str,  # Reason for disabling
  "drain_seconds": int = 30  # Grace period
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Disabled backend 'lm-studio': Overloaded",
  "backend": "lm-studio",
  "disabled_at": "2026-03-05T18:30:00Z",
  "reason": "Overloaded"
}
```

---

### **2.7 set_backend_weight**

Update a backend's routing weight.

**Permission**: `write`

**Parameters**:
```python
{
  "name": str,
  "weight": float,  # 0.0 to 1.0
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Updated zai weight from 0.3 to 0.5",
  "backend": "zai",
  "previous_weight": 0.3,
  "new_weight": 0.5,
  "normalized_weights": {
    "lm-studio": 0.5,
    "zai": 0.5
  }
}
```

---

### **2.8 test_backend**

Test a backend's connectivity and health.

**Permission**: `read`

**Parameters**:
```python
{
  "name": Optional[str],  # Test specific backend
  "url": Optional[str],  # Or test URL directly
  "timeout": float = 5.0  # Test timeout
}
```

**Returns**:
```json
{
  "backend": "zai",
  "url": "https://api.z.ai/api/coding/paas/v4",
  "healthy": true,
  "latency_ms": 150,
  "test_details": {
    "dns_lookup_ms": 20,
    "tcp_connect_ms": 30,
    "tls_handshake_ms": 50,
    "time_to_first_byte_ms": 100,
    "health_check": {
      "endpoint": "/v1/models",
      "status_code": 200,
      "response_time_ms": 50
    }
  }
}
```

---

## 3️⃣ Routing Control Tools

### **3.1 get_routing_rules**

Get current routing configuration.

**Permission**: `read`

**Parameters**: None

**Returns**:
```json
{
  "strategy": "weighted",
  "fallback_backend": "zai",
  "weights": {
    "lm-studio": 0.7,
    "zai": 0.3
  },
  "priorities": {
    "lm-studio": 1,
    "zai": 2
  },
  "rules": [
    {
      "condition": "model == 'glm-5'",
      "action": "route_to",
      "backend": "zai"
    }
  ]
}
```

---

### **3.2 update_routing_weights**

Update routing weights for load balancing.

**Permission**: `write`

**Parameters**:
```python
{
  "weights": Dict[str, float],  # Backend -> weight mapping
  "normalize": bool = True  # Normalize weights to sum to 1.0
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Updated routing weights",
  "previous_weights": {
    "lm-studio": 0.7,
    "zai": 0.3
  },
  "new_weights": {
    "lm-studio": 0.5,
    "zai": 0.5
  },
  "normalized": true,
  "change_id": 124
}
```

---

### **3.3 set_fallback_backend**

Set which backend to use as fallback.

**Permission**: `write`

**Parameters**:
```python
{
  "backend": str,  # Backend name
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Set fallback backend to 'zai'",
  "previous_fallback": "lm-studio",
  "new_fallback": "zai"
}
```

---

### **3.4 optimize_routing**

AI-powered routing optimization.

**Permission**: `write`

**Parameters**:
```python
{
  "objective": str,  # "performance", "cost", "reliability"
  "duration": int = 3600,  # Analysis duration (seconds)
  "dry_run": bool = True  # Preview without applying
}
```

**Returns**:
```json
{
  "analysis_period": "2026-03-05T17:00:00Z to 2026-03-05T18:00:00Z",
  "current_config": {
    "weights": {"lm-studio": 0.7, "zai": 0.3},
    "metrics": {
      "avg_latency_ms": 600,
      "error_rate": 0.05,
      "cost_per_1k_requests": 12.50
    }
  },
  "recommended_config": {
    "weights": {"lm-studio": 0.5, "zai": 0.5},
    "expected_metrics": {
      "avg_latency_ms": 500,  # -16.7%
      "error_rate": 0.02,     # -60%
      "cost_per_1k_requests": 15.20  # +21.6%
    }
  },
  "recommendation": "Use recommended config for better latency and reliability",
  "confidence": 0.85,
  "applied": false  # True if actually applied
}
```

---

### **3.5 get_routing_metrics**

Get routing performance metrics.

**Permission**: `read`

**Parameters**:
```python
{
  "time_range_seconds": int = 3600,  # Last hour
  "granularity": str = "5m"  # "1m", "5m", "15m", "1h"
}
```

**Returns**:
```json
{
  "time_range": "2026-03-05T17:00:00Z to 2026-03-05T18:00:00Z",
  "total_requests": 45000,
  "requests_by_backend": {
    "lm-studio": 31500,
    "zai": 13500
  },
  "avg_latency_ms": 600,
  "p95_latency_ms": 1200,
  "p99_latency_ms": 2000,
  "error_rate": 0.05,
  "backend_metrics": {
    "lm-studio": {
      "requests": 31500,
      "avg_latency_ms": 450,
      "error_rate": 0.08
    },
    "zai": {
      "requests": 13500,
      "avg_latency_ms": 900,
      "error_rate": 0.01
    }
  }
}
```

---

## 4️⃣ Cache Management Tools

### **4.1 get_cache_stats**

Get cache statistics and performance.

**Permission**: `read`

**Parameters**:
```python
{
  "cache_type": str = "all"  # "semantic", "redis", "mcp_tool", "response", "all"
}
```

**Returns**:
```json
{
  "semantic_cache": {
    "enabled": true,
    "hit_rate": 0.65,
    "miss_rate": 0.35,
    "total_entries": 1250,
    "memory_mb": 250,
    "ttl": 300,
    "evictions": 125
  },
  "redis_cache": {
    "enabled": true,
    "hit_rate": 0.82,
    "miss_rate": 0.18,
    "total_keys": 5000,
    "memory_mb": 500,
    "ttl": 3600
  },
  "mcp_tool_cache": {
    "enabled": true,
    "hit_rate": 0.95,
    "total_tools": 25,
    "cache_age_seconds": 180
  },
  "overall": {
    "total_requests": 100000,
    "cache_hits": 75000,
    "cache_misses": 25000,
    "overall_hit_rate": 0.75
  }
}
```

---

### **4.2 clear_cache**

Clear cache entries.

**Permission**: `write`

**Parameters**:
```python
{
  "cache_type": str,  # "semantic", "redis", "mcp_tool", "response", "all"
  "pattern": Optional[str],  # Key pattern to clear (e.g., "user:*")
  "confirm": bool = False  # Required for "all" cache
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Cleared semantic cache",
  "cache_type": "semantic",
  "entries_cleared": 1250,
  "memory_freed_mb": 250,
  "cleared_at": "2026-03-05T18:30:00Z"
}
```

---

### **4.3 warmup_cache**

Warm up cache with common queries.

**Permission**: `write`

**Parameters**:
```python
{
  "cache_type": str = "semantic",
  "queries": List[str],  # Queries to cache
  "max_concurrent": int = 5  # Concurrent warmup requests
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Warmed up semantic cache with 10 queries",
  "queries_processed": 10,
  "queries_successful": 10,
  "queries_failed": 0,
  "duration_seconds": 15,
  "entries_added": 10
}
```

---

### **4.4 set_cache_ttl**

Adjust cache time-to-live.

**Permission**: `write`

**Parameters**:
```python
{
  "cache_type": str,
  "ttl_seconds": int,  # 60 to 3600
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Set semantic cache TTL to 600s",
  "cache_type": "semantic",
  "previous_ttl": 300,
  "new_ttl": 600,
  "expected_impact": "Hit rate will increase, staleness will increase"
}
```

---

### **4.5 invalidate_cache_key**

Invalidate a specific cache key.

**Permission**: `write`

**Parameters**:
```python
{
  "cache_type": str,
  "key": str,  # Key to invalidate
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Invalidated cache key 'user:12345:profile'",
  "cache_type": "semantic",
  "key": "user:12345:profile",
  "key_existed": true
}
```

---

### **4.6 optimize_cache**

AI-powered cache optimization.

**Permission**: `write`

**Parameters**: None

**Returns**:
```json
{
  "analysis": {
    "semantic_cache": {
      "current_hit_rate": 0.35,
      "issue": "Low hit rate",
      "recommendation": {
        "action": "increase_ttl",
        "from": 300,
        "to": 600,
        "expected_improvement": "+20% hit rate",
        "reason": "Short TTL causes cache misses"
      }
    },
    "redis_cache": {
      "current_hit_rate": 0.82,
      "issue": "None",
      "recommendation": "No changes needed"
    }
  },
  "overall_recommendations": [
    {
      "priority": "high",
      "action": "Increase semantic cache TTL",
      "expected_impact": "+20% hit rate, -15% latency"
    },
    {
      "priority": "medium",
      "action": "Warm up semantic cache with common queries",
      "expected_impact": "-25% cold start latency"
    }
  ]
}
```

---

### **4.7 set_cache_size**

Adjust cache size limits.

**Permission**: `write`

**Parameters**:
```python
{
  "cache_type": str,
  "max_size_mb": int,  # Maximum size in MB
}
```

**Returns**:
```json
{
  "success": true,
  "message": "Set semantic cache size to 500MB",
  "cache_type": "semantic",
  "previous_size_mb": 250,
  "new_size_mb": 500,
  "memory_available_mb": 2048,
  "warning": "Large cache may increase memory usage"
}
```

---

## 5️⃣ Observability & Diagnostics Tools

### **5.1 get_metrics**

Get gateway performance metrics.

**Permission**: `read`

**Parameters**:
```python
{
  "time_range_seconds": int = 3600,  # Analysis period
  "granularity": str = "5m",  # "1m", "5m", "15m", "1h"
  "include_breakdown": bool = True
}
```

**Returns**:
```json
{
  "time_range": "2026-03-05T17:00:00Z to 2026-03-05T18:00:00Z",
  "summary": {
    "total_requests": 45000,
    "requests_per_second": 12.5,
    "avg_latency_ms": 600,
    "p95_latency_ms": 1200,
    "p99_latency_ms": 2000,
    "error_rate": 0.05,
    "success_rate": 0.95
  },
  "breakdown": {
    "by_backend": {
      "lm-studio": {"requests": 31500, "avg_latency_ms": 450, "error_rate": 0.08},
      "zai": {"requests": 13500, "avg_latency_ms": 900, "error_rate": 0.01}
    },
    "by_model": {
      "qwen-7b": {"requests": 20000, "avg_latency_ms": 400},
      "glm-4.7": {"requests": 15000, "avg_latency_ms": 800},
      "glm-5": {"requests": 10000, "avg_latency_ms": 1200}
    },
    "by_endpoint": {
      "/v1/chat/completions": {"requests": 40000, "avg_latency_ms": 650},
      "/v1/completions": {"requests": 5000, "avg_latency_ms": 300}
    }
  }
}
```

---

### **5.2 get_health**

Get gateway health status.

**Permission**: `read`

**Parameters**: None

**Returns**:
```json
{
  "status": "healthy",
  "health_score": 0.85,
  "components": {
    "gateway": {"status": "healthy", "uptime_seconds": 86400},
    "backends": {
      "lm-studio": {"status": "unhealthy", "error_rate": 0.80},
      "zai": {"status": "healthy", "error_rate": 0.01}
    },
    "cache": {"status": "healthy", "hit_rate": 0.75},
    "mcp_servers": {"status": "healthy", "servers_healthy": 4}
  },
  "alerts": [
    {
      "severity": "high",
      "component": "lm-studio",
      "message": "80% error rate detected"
    }
  ]
}
```

---

### **5.3 get_logs**

Get gateway logs.

**Permission**: `read`

**Parameters**:
```python
{
  "component": str = "all",  # "gateway", "backends", "cache", "mcp"
  "level": str = "INFO",  # "DEBUG", "INFO", "WARNING", "ERROR"
  "lines": int = 100,  # Number of lines
  "since": Optional[str]  # ISO8601 timestamp
}
```

**Returns**:
```json
{
  "logs": [
    {
      "timestamp": "2026-03-05T18:25:00Z",
      "level": "INFO",
      "component": "gateway",
      "message": "Request to lm-studio failed",
      "details": {"backend": "lm-studio", "error": "Connection refused"}
    }
  ],
  "total_lines": 100,
  "filtered_by": {
    "component": "all",
    "level": "INFO"
  }
}
```

---

### **5.4 trace_request**

Trace a request through the gateway.

**Permission**: `read`

**Parameters**:
```python
{
  "request_id": str  # Request ID to trace
}
```

**Returns**:
```json
{
  "request_id": "req-abc123",
  "trace": [
    {
      "component": "gateway",
      "event": "request_received",
      "timestamp": "2026-03-05T18:25:00.000Z",
      "details": {"path": "/v1/chat/completions", "method": "POST"}
    },
    {
      "component": "router",
      "event": "backend_selected",
      "timestamp": "2026-03-05T18:25:00.010Z",
      "details": {"backend": "lm-studio", "reason": "weighted_selection"}
    },
    {
      "component": "cache",
      "event": "cache_miss",
      "timestamp": "2026-03-05T18:25:00.020Z",
      "details": {"cache_type": "semantic", "key": "query:123"}
    },
    {
      "component": "backend",
      "event": "request_sent",
      "timestamp": "2026-03-05T18:25:00.030Z",
      "details": {"backend": "lm-studio", "url": "http://127.0.0.1:1234/v1/chat/completions"}
    },
    {
      "component": "backend",
      "event": "response_received",
      "timestamp": "2026-03-05T18:25:00.500Z",
      "details": {"backend": "lm-studio", "status_code": 200, "latency_ms": 470}
    },
    {
      "component": "gateway",
      "event": "response_sent",
      "timestamp": "2026-03-05T18:25:00.510Z",
      "details": {"total_latency_ms": 510}
    }
  ],
  "summary": {
    "total_latency_ms": 510,
    "backend": "lm-studio",
    "status_code": 200,
    "cache_hits": 0,
    "cache_misses": 1
  }
}
```

---

### **5.5 diagnose_issues**

AI-powered issue diagnosis.

**Permission**: `read`

**Parameters**: None

**Returns**:
```json
{
  "health_score": 0.45,
  "issues": [
    {
      "severity": "high",
      "component": "lm-studio-backend",
      "problem": "80% error rate",
      "root_cause": "Backend overloaded",
      "impact": "High latency, poor user experience",
      "recommendation": {
        "action": "disable_backend",
        "backend": "lm-studio",
        "duration": "temporary",
        "reason": "Protect user experience"
      },
      "estimated_impact": "Reduce errors from 80% to <5%"
    },
    {
      "severity": "medium",
      "component": "semantic-cache",
      "problem": "Low hit rate (35%)",
      "root_cause": "TTL too short",
      "impact": "Increased latency, higher backend load",
      "recommendation": {
        "action": "increase_ttl",
        "from": 300,
        "to": 600,
        "expected_improvement": "+20% hit rate"
      }
    }
  ],
  "action_items": [
    {
      "priority": 1,
      "action": "Disable lm-studio backend",
      "command": "disable_backend('lm-studio', 'Overloaded')"
    },
    {
      "priority": 2,
      "action": "Increase semantic cache TTL",
      "command": "set_cache_ttl('semantic', 600)"
    },
    {
      "priority": 3,
      "action": "Monitor for 5 minutes",
      "command": "get_health()"
    }
  ],
  "auto_fix_available": true  # Can AI auto-fix?
}
```

---

### **5.6 get_performance_report**

Generate comprehensive performance report.

**Permission**: `read`

**Parameters**:
```python
{
  "duration_seconds": int = 3600,  # Report period
  "include_recommendations": bool = True
}
```

**Returns**:
```json
{
  "report_period": "2026-03-05T17:00:00Z to 2026-03-05T18:00:00Z",
  "summary": {
    "total_requests": 45000,
    "avg_latency_ms": 600,
    "p95_latency_ms": 1200,
    "p99_latency_ms": 2000,
    "error_rate": 0.05,
    "throughput_requests_per_second": 12.5
  },
  "performance_by_backend": {
    "lm-studio": {
      "requests": 31500,
      "avg_latency_ms": 450,
      "error_rate": 0.08,
      "grade": "C"  # High errors
    },
    "zai": {
      "requests": 13500,
      "avg_latency_ms": 900,
      "error_rate": 0.01,
      "grade": "A"
    }
  },
  "trends": {
    "latency_trend": "increasing",  # +15% over period
    "error_rate_trend": "stable",
    "throughput_trend": "stable"
  },
  "recommendations": [
    "Consider increasing ZAI weight to reduce latency",
    "Investigate LM Studio errors",
    "Cache optimization could improve performance"
  ]
}
```

---

## 6️⃣ Advanced AI Optimization Tools

### **6.1 optimize_performance**

AI-powered performance optimization.

**Permission**: `write`

**Parameters**:
```python
{
  "dry_run": bool = True,  # Preview changes
  "duration_seconds": int = 3600,  # Analysis period
}
```

**Returns**:
```json
{
  "analysis_period": "Last 1 hour",
  "current_config": {
    "routing_weights": {"lm-studio": 0.7, "zai": 0.3},
    "cache_ttl": {"semantic": 300, "redis": 3600}
  },
  "recommended_config": {
    "routing_weights": {"lm-studio": 0.4, "zai": 0.6},
    "cache_ttl": {"semantic": 600, "redis": 3600}
  },
  "expected_improvement": {
    "avg_latency_ms": {
      "current": 600,
      "optimized": 480,  # -20%
      "improvement": "-20%"
    },
    "p95_latency_ms": {
      "current": 1200,
      "optimized": 900,
      "improvement": "-25%"
    },
    "cache_hit_rate": {
      "current": 0.65,
      "optimized": 0.78,
      "improvement": "+20%"
    }
  },
  "confidence": 0.82,
  "recommendations": [
    "Increase ZAI weight (better performance)",
    "Increase semantic cache TTL (better hit rate)"
  ],
  "applied": false
}
```

---

### **6.2 optimize_cost**

AI-powered cost optimization.

**Permission**: `write`

**Parameters**:
```python
{
  "budget_per_hour": Optional[float],  # Target budget
  "dry_run": bool = True
}
```

**Returns**:
```json
{
  "analysis_period": "Last 24 hours",
  "current_cost_per_hour": 15.20,
  "current_cost_per_1k_requests": 12.50,
  "recommended_config": {
    "routing_strategy": "cost_aware",
    "prefer_local": true,
    "cache_ttl": {"semantic": 900}  # Longer TTL = fewer requests
  },
  "expected_savings": {
    "cost_per_hour": 12.30,
    "savings_per_hour": 2.90,
    "savings_percentage": 19.1
  },
  "trade_offs": [
    "Cost savings will increase latency by ~15%",
    "Local backend may get overloaded"
  ]
}
```

---

### **6.3 optimize_reliability**

AI-powered reliability optimization.

**Permission**: `write`

**Parameters**:
```python
{
  "target_error_rate": float = 0.01,  # Target error rate
  "dry_run": bool = True
}
```

**Returns**:
```json
{
  "current_error_rate": 0.05,
  "target_error_rate": 0.01,
  "recommended_config": {
    "routing": {
      "strategy": "health_aware",
      "weights": {"lm-studio": 0.2, "zai": 0.8},
      "circuit_breaker": {
        "lm-studio": {
          "error_threshold": 0.5,
          "half_open_timeout": 60
        }
      }
    },
    "timeout": {
      "lm-studio": 5.0,
      "zai": 30.0
    }
  },
  "expected_error_rate": 0.008,
  "expected_improvement": "-84% error rate",
  "trade_offs": [
    "Higher cost (more ZAI usage)",
    "Increased latency (more timeouts)"
  ]
}
```

---

### **6.4 run_ab_test**

Run an A/B test.

**Permission**: `write`

**Parameters**:
```python
{
  "test_name": str,
  "control_config": dict,  # Control configuration
  "experiment_config": dict,  # Experiment configuration
  "duration_seconds": int = 3600,  # Test duration
  "traffic_split": float = 0.5,  # 50% traffic each
  "success_metric": str = "latency"  # "latency", "error_rate", "cost"
}
```

**Returns**:
```json
{
  "test_id": "ab-test-123",
  "test_name": "routing-weight-optimization",
  "status": "running",
  "started_at": "2026-03-05T18:30:00Z",
  "estimated_end": "2026-03-05T19:30:00Z",
  "config": {
    "control": {"weights": {"lm-studio": 0.7, "zai": 0.3}},
    "experiment": {"weights": {"lm-studio": 0.5, "zai": 0.5}},
    "traffic_split": 0.5
  },
  "monitoring_url": "/ab-tests/ab-test-123"
}
```

---

### **6.5 get_ab_test_results**

Get A/B test results.

**Permission**: `read`

**Parameters**:
```python
{
  "test_id": str
}
```

**Returns**:
```json
{
  "test_id": "ab-test-123",
  "test_name": "routing-weight-optimization",
  "status": "completed",
  "duration_seconds": 3600,
  "results": {
    "control": {
      "config": {"weights": {"lm-studio": 0.7, "zai": 0.3}},
      "metrics": {
        "requests": 22500,
        "avg_latency_ms": 600,
        "error_rate": 0.05,
        "cost": 12.50
      }
    },
    "experiment": {
      "config": {"weights": {"lm-studio": 0.5, "zai": 0.5}},
      "metrics": {
        "requests": 22500,
        "avg_latency_ms": 480,
        "error_rate": 0.02,
        "cost": 15.20
      }
    }
  },
  "winner": "experiment",
  "significance": 0.95,  # Statistical significance
  "recommendation": "Use experiment config (better latency and errors)",
  "can_apply": true
}
```

---

## 🔒 Permission Matrix Summary

| Tool Category | Read | Write | Admin |
|---------------|------|-------|-------|
| **Configuration** |
| get_config | ✅ | ✅ | ✅ |
| update_config | ❌ | ✅ | ✅ |
| reset_config | ❌ | ✅ | ✅ |
| reload_config | ❌ | ✅ | ✅ |
| validate_config | ✅ | ✅ | ✅ |
| get_config_diff | ✅ | ✅ | ✅ |
| rollback_config | ❌ | ✅ | ✅ |
| **Backends** |
| list_backends | ✅ | ✅ | ✅ |
| get_backend_info | ✅ | ✅ | ✅ |
| add_backend | ❌ | ✅ | ✅ |
| remove_backend | ❌ | ❌ | ✅ |
| enable_backend | ❌ | ✅ | ✅ |
| disable_backend | ❌ | ✅ | ✅ |
| set_backend_weight | ❌ | ✅ | ✅ |
| test_backend | ✅ | ✅ | ✅ |
| **Routing** |
| get_routing_rules | ✅ | ✅ | ✅ |
| update_routing_weights | ❌ | ✅ | ✅ |
| set_fallback_backend | ❌ | ✅ | ✅ |
| optimize_routing | ❌ | ✅ | ✅ |
| get_routing_metrics | ✅ | ✅ | ✅ |
| **Cache** |
| get_cache_stats | ✅ | ✅ | ✅ |
| clear_cache | ❌ | ✅ | ✅ |
| warmup_cache | ❌ | ✅ | ✅ |
| set_cache_ttl | ❌ | ✅ | ✅ |
| invalidate_cache_key | ❌ | ✅ | ✅ |
| optimize_cache | ❌ | ✅ | ✅ |
| set_cache_size | ❌ | ✅ | ✅ |
| **Observability** |
| get_metrics | ✅ | ✅ | ✅ |
| get_health | ✅ | ✅ | ✅ |
| get_logs | ✅ | ✅ | ✅ |
| trace_request | ✅ | ✅ | ✅ |
| diagnose_issues | ✅ | ✅ | ✅ |
| get_performance_report | ✅ | ✅ | ✅ |
| **Advanced** |
| optimize_performance | ❌ | ✅ | ✅ |
| optimize_cost | ❌ | ✅ | ✅ |
| optimize_reliability | ❌ | ✅ | ✅ |
| run_ab_test | ❌ | ✅ | ✅ |
| get_ab_test_results | ✅ | ✅ | ✅ |

---

## 📝 Next Steps

With this complete API surface design, we can now:

1. **Begin Implementation**: Start coding the MCP server with these tools
2. **Create Validation Schemas**: Define Pydantic models for all parameters
3. **Implement Authentication**: Build the auth and authorization system
4. **Add Unit Tests**: Create tests for each tool
5. **Write Examples**: Document usage examples for each tool

---

**Last Updated**: 2026-03-05
**Status**: ✅ Design Complete, Ready for Implementation
**Total Tools**: 38 tools across 6 categories
