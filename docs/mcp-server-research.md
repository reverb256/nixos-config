# MCP Server Implementation Patterns for Gateway Management

**Phase 1 Research**: MCP Server Patterns for Infrastructure Management

## Executive Summary

This document synthesizes research on MCP (Model Context Protocol) server implementations for infrastructure management, analyzing best practices, security patterns, and architectural approaches for building AI-manageable systems.

**Key Finding**: stdio-based MCP servers are the recommended approach for gateway management due to security, performance, and simplicity. HTTP/SSE servers should be reserved for remote management scenarios.

---

## 📚 Reference Implementations Analyzed

### **1. Claude Code's Built-in MCP Servers**

**Type**: stdio + HTTP/SSE

**Architecture**:
```
Claude Code
├── stdio servers (local processes)
│   ├── filesystem server
│   ├── database server
│   └── custom tool servers
└── SSE servers (cloud services)
    ├── GitHub MCP
    ├── Asana MCP
    └── Google Drive MCP
```

**Best Practices Observed**:
- ✅ **Local Operations via stdio**: Fast, secure, no network overhead
- ✅ **Cloud Services via SSE**: OAuth authentication, auto-discovery
- ✅ **Tool Naming**: `mcp__plugin_<plugin>_<server>__<tool>` format
- ✅ **Error Handling**: Graceful degradation, clear error messages
- ✅ **Validation**: Input validation before operations
- ✅ **Logging**: Comprehensive logging for debugging

**Lessons for Gateway**:
- Use stdio for local gateway management (fast, secure)
- Clear tool naming conventions
- Comprehensive error handling and logging
- Input validation is critical

---

### **2. Kubernetes MCP Server**

**Type**: HTTP

**Architecture**:
```
Kubernetes MCP Server
├── Authentication: Kubeconfig + ServiceAccount
├── Tools:
│   ├── list_pods
│   ├── list_deployments
│   ├── get_logs
│   └── exec_command (dangerous!)
└── Authorization: RBAC checks
```

**Security Patterns**:
- ✅ **Authentication**: Uses kubeconfig credentials
- ✅ **Authorization**: RBAC checks before operations
- ✅ **Dangerous Tool Restrictions**: `exec_command` requires explicit permission
- ✅ **Audit Logging**: All operations logged
- ⚠️ **Risk**: Running commands in pods is inherently risky

**Lessons for Gateway**:
- Implement RBAC-like permission model (read/write/admin)
- Explicitly mark dangerous operations
- Require extra permissions for critical changes
- Comprehensive audit logging is non-negotiable

---

### **3. Database MCP Servers (PostgreSQL, MySQL)**

**Type**: stdio

**Architecture**:
```
Database MCP Server
├── Connection Pool Management
├── Tools:
│   ├── query (read-only)
│   ├── execute_write (write permission)
│   ├── get_schema (read-only)
│   └── backup (admin permission)
└── Safety Mechanisms:
    ├── Query timeout (5s default)
    ├── Result set limits (1000 rows)
    ├── Read-only replicas for queries
    └── Write confirmations
```

**Best Practices Observed**:
- ✅ **Timeout Protection**: All operations timeout
- ✅ **Result Limits**: Prevent large result sets
- ✅ **Read Replicas**: Queries don't impact production
- ✅ **Write Confirmations**: Explicit approval for writes
- ✅ **Connection Pooling**: Efficient resource usage

**Lessons for Gateway**:
- Implement timeout protection for all operations
- Limit result sets (e.g., max 100 metrics entries)
- Use connection pooling for HTTP clients
- Require confirmation for dangerous changes

---

### **4. Infrastructure Management MCP Servers**

**Type**: stdio

**Examples**: Terraform MCP, Ansible MCP, Pulumi MCP

**Architecture**:
```
Infrastructure MCP Server
├── Tools:
│   ├── get_state (read current state)
│   ├── plan_changes (preview changes)
│   ├── apply_changes (execute changes)
│   └── rollback (revert changes)
└── Safety Mechanisms:
    ├── Dry-run Mode (preview only)
    ├── Change Validation
    ├── Approval Workflow
    └── Rollback Capability
```

**Best Practices Observed**:
- ✅ **Dry-Run Mode**: Preview changes before applying
- ✅ **Change Validation**: Validate before execution
- ✅ **Approval Workflow**: Require explicit approval
- ✅ **Rollback**: Easy reversion of changes
- ✅ **State Management**: Track current vs desired state

**Lessons for Gateway**:
- Implement dry-run mode for all write operations
- Validate configuration changes before applying
- Track change history for rollback
- Require approval for dangerous operations

---

## 🏗️ Recommended MCP Server Architecture

### **Transport Layer: stdio**

**Why stdio over HTTP/SSE**:

| Aspect | stdio | HTTP/SSE |
|--------|-------|----------|
| **Security** | ✅ Local only, no network attack surface | ❌ Requires auth, more attack surface |
| **Performance** | ✅ No network overhead (~1ms calls) | ⚠️ Network latency (~10-50ms) |
| **Reliability** | ✅ No network failures | ⚠️ Network issues possible |
| **Authentication** | ✅ Process-based (implicit) | ❌ Requires token management |
| **Simplicity** | ✅ Simple setup | ⚠️ More complex (CORS, auth, etc.) |
| **Remote Access** | ❌ Local only | ✅ Can access remotely |

**Recommendation**: Use **stdio** for gateway management. Claude Code runs on the same machine as the gateway, so remote access isn't needed.

---

### **Process Architecture**

```
Gateway Process (main.py)
    ↓
    MCP Server Process (gateway_mcp_server.py)
    ↓
    stdio Communication (JSON-RPC 2.0)
    ↓
    Claude Code (MCP Client)
```

**Implementation**:
```python
# gateway_mcp_server.py
import asyncio
from mcp.server import Server
from mcp.server.stdio import stdio_server

# Create MCP server
gateway_mcp = Server("ai-inference-gateway")

# Register tools
@gateway_mcp.tool()
async def get_config(section: str = None) -> dict:
    """Get gateway configuration."""
    # Import gateway state
    from ai_inference_gateway.main import gateway_state
    # Return config
    return gateway_state.config.to_dict()

# Start server
async def main():
    async with stdio_server() as streams:
        await gateway_mcp.run(
            streams[0], streams[1], gateway_mcp.create_initialization_options()
        )

if __name__ == "__main__":
    asyncio.run(main())
```

---

## 🔒 Security Best Practices

### **1. Permission Model**

**Three-Tier Permission System**:

```python
class Permission(Enum):
    """Permission levels for MCP tools."""
    READ = "read"           # View configuration, metrics, logs
    WRITE = "write"         # Modify configuration, backends
    ADMIN = "admin"         # Dangerous operations (remove backends, etc.)

# API Keys with Permissions
API_KEYS = {
    "claude-code-manage": [Permission.READ, Permission.WRITE],
    "ops-ai-admin": [Permission.READ, Permission.WRITE, Permission.ADMIN],
    "monitoring-bot": [Permission.READ]
}
```

**Permission Matrix**:

| Tool Category | Read | Write | Admin |
|---------------|------|-------|-------|
| Get configuration | ✅ | ✅ | ✅ |
| Get metrics | ✅ | ✅ | ✅ |
| Get health | ✅ | ✅ | ✅ |
| Update config | ❌ | ✅ | ✅ |
| Add backend | ❌ | ✅ | ✅ |
| Remove backend | ❌ | ❌ | ✅ |
| Clear all caches | ❌ | ✅ | ✅ |
| Shutdown gateway | ❌ | ❌ | ✅ |

---

### **2. Authentication**

**Token-Based Authentication**:

```python
class MCPAuthenticator:
    """Authenticate MCP tool calls."""

    API_KEYS = {
        "claude-code-manage": {
            "hash": "sha256:abc123...",
            "permissions": ["read", "write"]
        },
        "ops-ai-admin": {
            "hash": "sha256:def456...",
            "permissions": ["read", "write", "admin"]
        }
    }

    def authenticate(self, token: str) -> Optional[List[str]]:
        """Verify token and return permissions."""
        # Check token against API_KEYS
        # Return permissions or None if invalid
        pass

    def check_permission(self, token: str, required_permission: str) -> bool:
        """Check if token has required permission."""
        permissions = self.authenticate(token)
        if permissions is None:
            return False
        return required_permission in permissions
```

**Usage**:
```python
@mcp.tool()
async def update_config(
    section: str,
    key: str,
    value: Any,
    token: str  # Passed automatically by MCP client
) -> str:
    """Update configuration (requires write permission)."""

    # Check authentication
    if not authenticator.check_permission(token, "write"):
        raise PermissionError("Insufficient permissions")

    # Apply change
    # ...
```

---

### **3. Input Validation**

**Comprehensive Validation**:

```python
from pydantic import BaseModel, Field, validator

class UpdateConfigParams(BaseModel):
    """Validate update_config parameters."""

    section: str = Field(..., regex="^(routing|cache|backends|logging)$")
    key: str = Field(..., min_length=1, max_length=50)
    value: Any

    @validator('section')
    def validate_section(cls, v):
        """Validate section is allowed."""
        allowed_sections = ["routing", "cache", "backends", "logging"]
        if v not in allowed_sections:
            raise ValueError(f"Invalid section. Must be one of: {allowed_sections}")
        return v

class AddBackendParams(BaseModel):
    """Validate add_backend parameters."""

    name: str = Field(..., min_length=1, max_length=50)
    url: str = Field(..., regex=r"^https?://")
    type: str = Field(..., regex="^(lm-studio|zai|kilo)$")
    weight: float = Field(..., ge=0.0, le=1.0)

    @validator('url')
    def validate_url(cls, v):
        """Validate URL is reachable."""
        # Test connectivity
        # ...
        return v
```

---

### **4. Audit Logging**

**Comprehensive Audit Trail**:

```python
import logging
from datetime import datetime

audit_logger = logging.getLogger("mcp_audit")

async def log_operation(
    operation: str,
    token: str,
    params: dict,
    result: str,
    error: Optional[str] = None
):
    """Log MCP operation to audit trail."""

    log_entry = {
        "timestamp": datetime.utcnow().isoformat(),
        "operation": operation,
        "token_hash": hashlib.sha256(token.encode()).hexdigest()[:16],
        "params": {k: str(v)[:100] for k, v in params.items()},  # Truncate long values
        "result": result,
        "error": error
    }

    audit_logger.info(json.dumps(log_entry))

    # Also write to audit log file
    with open("/var/log/ai-gateway/mcp-audit.log", "a") as f:
        f.write(json.dumps(log_entry) + "\n")
```

**Audit Log Format**:
```json
{
  "timestamp": "2026-03-05T18:30:00Z",
  "operation": "update_config",
  "token_hash": "a3f5c8d2...",
  "params": {
    "section": "routing",
    "key": "weight",
    "value": "0.8"
  },
  "result": "success",
  "error": null
}
```

---

### **5. Rate Limiting**

**Prevent Abuse**:

```python
from collections import defaultdict
import time

class RateLimiter:
    """Rate limit MCP tool calls."""

    def __init__(self, max_requests_per_minute: int = 100):
        self.max_requests = max_requests_per_minute
        self.requests = defaultdict(list)

    def check_rate_limit(self, token: str) -> bool:
        """Check if token has exceeded rate limit."""

        now = time.time()
        minute_ago = now - 60

        # Clean old requests
        self.requests[token] = [
            req_time for req_time in self.requests[token]
            if req_time > minute_ago
        ]

        # Check limit
        if len(self.requests[token]) >= self.max_requests:
            return False

        # Add current request
        self.requests[token].append(now)
        return True

# Usage
rate_limiter = RateLimiter(max_requests_per_minute=100)

@mcp.tool()
async def update_config(...):
    # Check rate limit
    if not rate_limiter.check_rate_limit(token):
        raise RateLimitError("Too many requests")
```

---

## ⚠️ Common Pitfalls & Anti-Patterns

### **Anti-Pattern #1: No Input Validation**

**❌ Bad**:
```python
@mcp.tool()
async def update_backend_weight(backend: str, weight: float):
    """Update backend weight."""
    # No validation - weight could be anything!
    gateway_state.backends[backend].weight = weight
```

**✅ Good**:
```python
@mcp.tool()
async def update_backend_weight(
    backend: str,
    weight: float
) -> str:
    """Update backend weight."""

    # Validate backend exists
    if backend not in gateway_state.backends:
        raise ValueError(f"Backend {backend} not found")

    # Validate weight range
    if not 0 <= weight <= 1:
        raise ValueError(f"Weight must be between 0 and 1, got {weight}")

    # Apply change
    gateway_state.backends[backend].weight = weight
    return f"Updated {backend} weight to {weight}"
```

---

### **Anti-Pattern #2: No Confirmation for Dangerous Operations**

**❌ Bad**:
```python
@mcp.tool()
async def remove_backend(backend: str):
    """Remove backend immediately - dangerous!"""
    del gateway_state.backends[backend]
```

**✅ Good**:
```python
@mcp.tool()
async def remove_backend(
    backend: str,
    confirm: bool = False
) -> str:
    """Remove backend (requires confirmation)."""

    if not confirm:
        return (
            f"⚠️ This will remove backend '{backend}'.\n"
            f"Current backends: {list(gateway_state.backends.keys())}\n"
            f"To confirm, call with confirm=true"
        )

    # Check if this is the last backend
    if len(gateway_state.backends) == 1:
        raise ValueError("Cannot remove the last backend")

    # Remove backend
    del gateway_state.backends[backend]
    return f"Removed backend '{backend}'"
```

---

### **Anti-Pattern #3: No Rollback Capability**

**❌ Bad**:
```python
@mcp.tool()
async def update_config(section, key, value):
    """Update config - no way to undo!"""
    gateway_state.config[section][key] = value
```

**✅ Good**:
```python
class ConfigManager:
    def __init__(self):
        self.change_history = []  # Track all changes
        self.max_history = 10

    async def update_config(self, section, key, value):
        """Update config with rollback capability."""

        # Save current state for rollback
        old_value = gateway_state.config[section][key]

        # Apply change
        gateway_state.config[section][key] = value

        # Save to history
        self.change_history.append({
            "timestamp": datetime.utcnow(),
            "section": section,
            "key": key,
            "old_value": old_value,
            "new_value": value
        })

        # Limit history size
        if len(self.change_history) > self.max_history:
            self.change_history.pop(0)

    async def rollback_config(self, change_id: int):
        """Rollback specific change."""
        if 0 <= change_id < len(self.change_history):
            change = self.change_history[change_id]
            # Restore old value
            gateway_state.config[change["section"]][change["key"]] = change["old_value"]
            return f"Rolled back change {change_id}"
```

---

### **Anti-Pattern #4: No Timeout Protection**

**❌ Bad**:
```python
@mcp.tool()
async def test_backend(url: str):
    """Test backend - could hang forever!"""
    response = await httpx.AsyncClient().get(f"{url}/health")
```

**✅ Good**:
```python
@mcp.tool()
async def test_backend(url: str, timeout: float = 5.0) -> dict:
    """Test backend with timeout protection."""

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            response = await client.get(f"{url}/health")
            return {"healthy": response.status_code == 200}
    except httpx.TimeoutException:
        return {"healthy": False, "error": "Timeout"}
```

---

### **Anti-Pattern #5: Ignoring Errors**

**❌ Bad**:
```python
@mcp.tool()
async def add_backend(name, url, weight):
    """Add backend - errors silently ignored!"""
    backend = Backend(name, url, weight)
    gateway_state.backends[name] = backend
    # No error checking if backend is invalid
```

**✅ Good**:
```python
@mcp.tool()
async def add_backend(name: str, url: str, weight: float) -> str:
    """Add backend with comprehensive error handling."""

    try:
        # Validate inputs
        if name in gateway_state.backends:
            raise ValueError(f"Backend {name} already exists")

        if not 0 <= weight <= 1:
            raise ValueError(f"Weight must be 0-1, got {weight}")

        # Test connectivity
        healthy = await test_backend_connectivity(url)
        if not healthy:
            raise ValueError(f"Backend {url} is not healthy")

        # Add backend
        backend = Backend(name, url, weight)
        gateway_state.backends[name] = backend

        return f"Added backend {name}"

    except ValueError as e:
        logger.error(f"Failed to add backend: {e}")
        raise  # Re-raise to show error to user
    except Exception as e:
        logger.error(f"Unexpected error adding backend: {e}")
        raise RuntimeError(f"Failed to add backend: {e}")
```

---

## 🎯 Recommended Approach for Gateway

### **Architecture: stdio MCP Server**

**Configuration** (`.claude/plugin.json` or `.mcp.json`):

```json
{
  "gateway-management": {
    "command": "python",
    "args": [
      "-m",
      "ai_inference_gateway.gateway_mcp_server"
    ],
    "env": {
      "GATEWAY_STATE_PATH": "/var/lib/ai-gateway/state.json",
      "AUDIT_LOG_PATH": "/var/log/ai-gateway/mcp-audit.log"
    }
  }
}
```

**Tool Categories** (30+ tools):

1. **Configuration** (7 tools)
   - get_config, update_config, reset_config, reload_config
   - validate_config, get_config_diff, rollback_config

2. **Backends** (8 tools)
   - list_backends, get_backend_info, add_backend, remove_backend
   - enable_backend, disable_backend, set_backend_weight, test_backend

3. **Routing** (5 tools)
   - get_routing_rules, update_routing_weights, set_fallback_backend
   - optimize_routing, get_routing_metrics

4. **Cache** (7 tools)
   - get_cache_stats, clear_cache, warmup_cache, set_cache_ttl
   - invalidate_cache_key, optimize_cache, set_cache_size

5. **Observability** (6 tools)
   - get_metrics, get_health, get_logs, trace_request
   - diagnose_issues, get_performance_report

6. **Advanced** (5 tools)
   - optimize_performance, optimize_cost, optimize_reliability
   - run_ab_test, get_ab_test_results

---

## 📊 Decision Matrix: stdio vs HTTP

| Decision Factor | stdio | HTTP/SSE |
|-----------------|-------|----------|
| **Security** | ✅ Best (local only) | ⚠️ Requires auth |
| **Performance** | ✅ ~1ms latency | ⚠️ ~10-50ms latency |
| **Reliability** | ✅ No network issues | ⚠️ Network dependent |
| **Complexity** | ✅ Simple | ⚠️ More complex |
| **Remote Access** | ❌ Not possible | ✅ Possible |
| **Claude Code Integration** | ✅ Excellent | ✅ Good |

**Recommendation**: **stdio** for gateway management.

**Rationale**:
- Gateway and Claude Code run on same machine
- No need for remote access
- Best security and performance
- Simplest implementation

---

## ✅ Checklist for MCP Server Implementation

- [ ] Choose stdio transport (recommended)
- [ ] Implement permission model (read/write/admin)
- [ ] Add authentication (token-based)
- [ ] Implement audit logging
- [ ] Add rate limiting
- [ ] Input validation for all tools
- [ ] Timeout protection for all operations
- [ ] Error handling for all tools
- [ ] Rollback capability for changes
- [ ] Confirmation for dangerous operations
- [ ] Comprehensive documentation
- [ ] Example workflows
- [ ] Security audit
- [ ] Load testing

---

## 🔗 References

- **MCP Protocol Spec**: https://modelcontextprotocol.io/
- **MCP Python SDK**: https://github.com/modelcontextprotocol/python-sdk
- **Claude Code MCP Docs**: https://docs.claude.com/en/docs/claude-code/mcp
- **Kubernetes MCP**: https://github.com/modelcontextprotocol/kubernetes-mcp
- **PostgreSQL MCP**: https://github.com/modelcontextprotocol/postgres-mcp

---

**Last Updated**: 2026-03-05
**Next**: Design complete API surface (Phase 1.2)
