# Claude Code Guidelines - NixOS Configuration

This document contains insights and patterns for Claude Code agents working on this NixOS configuration, focusing on workflows, testing strategies, and common pitfalls.

## Claude Code-Specific Features

### Serena Semantic Coding Tools

Claude Code has access to Serena, which provides semantic code understanding:

- **find_symbol**: Find functions, classes, modules by name path
- **find_referencing_symbols**: Find all references to a symbol
- **get_symbols_overview**: Get file structure overview
- **replace_symbol_body**: Replace entire function/class bodies
- **replace_content**: Regex-based file editing
- **search_for_pattern**: Fast pattern-based search

### Onboarding System

The project has Serena onboarding configured. Memory files provide:
- `suggested_commands.md`: Development commands
- `style_and_conventions.md`: Code style patterns
- `task_completion.md`: Pre-completion checklist
- `project_overview.md`: Architecture and structure

### Multi-Server MCP Integration

Claude Code can access MCP servers directly:
- **Project MCPs** (.mcp.json): chrome-devtools, context7, fetch, filesystem, git, nixos, playwright
- **User MCPs**: web-reader, web-search-prime, zai-mcp-server, zread
- **Plugin MCPs**: pinecone, serena, sonatype-guide, etc.

---

---

## Claude Code Workflow

### Starting a Session

1. **Activate the nixos project** in Serena
2. **Check onboarding status** - memories are available for project context
3. **Use semantic tools** for code navigation (find_symbol, search_for_pattern)
4. **Read memories** before making major changes

### Recommended Tool Usage

| Task | Tool | Why |
|------|------|-----|
| Find a function | `find_symbol` | Fast, semantic search |
| Find all references | `find_referencing_symbols` | Accurate cross-references |
| Understand file structure | `get_symbols_overview` | Quick overview |
| Edit specific function | `replace_symbol_body` | Precise, reliable |
| Edit small section | `replace_content` | Regex-based, flexible |
| Search for pattern | `search_for_pattern` | Fast code search |

### Reading Strategy

1. **Always check memories first** - `read_memory` for relevant topic
2. **Use get_symbols_overview** before reading full files
3. **Use find_symbol with include_body** for specific functions
4. **Avoid reading entire files** unless absolutely necessary

---

### Building & Testing (Just Commands)

**IMPORTANT**: Always use the `justfile` recipes for building and testing. The just commands handle:
- Mining auto-pause during builds
- Cluster-wide deployments via colmena
- CI/CD pipeline integration
- Proper error handling and rollback

```bash
# Primary development workflow
just test              # Verify configuration (flake check + build all hosts)
just switch            # Apply to local host (auto-pauses mining)
just ci-local          # Run full CI pipeline locally
just deploy            # Deploy to all cluster hosts

# Single-host deployments
just zephyr            # Deploy to zephyr (local)
just nexus             # Deploy to nexus (remote)
just forge             # Deploy to forge (remote)
just sentry            # Deploy to sentry (remote)

# Utilities
just cluster-status    # Check connectivity of all nodes
just status            # Show git status on all nodes
just sync              # Sync all repos to current branch
just health-check      # Run cluster health check

# CI/CD
just flake-update      # Update flake.lock
just pre-commit-all    # Run pre-commit on all files
just ci-status         # Show CI/CD status
```

### Direct nixos-rebuild Commands (For Reference)

The just commands wrap these nixos-rebuild commands:

```bash
# Fast syntax check (5 seconds)
nix flake check

# Build without applying (1-2 minutes)
sudo nixos-rebuild build --flake .#zephyr

# Test configuration (applies changes, rolls back on reboot)
sudo nixos-rebuild test --flake .#zephyr

# Apply persistently
sudo nixos-rebuild switch --flake .#zephyr

# Update flake inputs
nix flake update
```

### Safe Rebuild with Mining Pause

**IMPORTANT**: All rebuild commands automatically pause mining to maximize build performance.

```bash
# Fish aliases (auto-pause mining)
nswitch      # nixos-rebuild switch
nswitchu     # switch with --upgrade
ntest        # nixos-rebuild test
nbuild       # nixos-rebuild build
ndry         # nixos-rebuild dry-activate

# Justfile recipe
just switch  # Auto-pauses mining

# Direct script
sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake .#zephyr
```

The `nixos-rebuild-safe.sh` script:
1. Stops `xmrig@*` and `lolminer-*` services
2. Runs the nixos-rebuild command
3. Automatically restarts mining (even if build fails)

### Service Management
```bash
# Check service status
systemctl status ai-inference-gateway

# View service logs
journalctl -u ai-inference-gateway -f

# Restart service
systemctl restart ai-inference-gateway

# Check if service is running
systemctl is-active ai-inference-gateway
```

### Gateway Testing
```bash
# Health check
curl http://127.0.0.1:8080/health | jq .

# List models
curl http://127.0.0.1:8080/v1/models | jq .

# Simple completion test
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/qwen3.5-9b","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' | jq .

# MCP tools list
curl http://127.0.0.1:8080/mcp/tools | jq .

# MCP tool call
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{"server":"web-search-prime","tool":"webSearchPrime","arguments":{"search_query":"NixOS"}}' | jq .
```

---

## Critical Patterns

### 1. Always Test Before Applying

**Pattern**: `just test` → `just zephyr` → `just deploy`

**Why**: NixOS configurations can have complex dependencies. Testing incrementally catches errors early.

```bash
# Step 1: Fast syntax and build check (1-2 minutes)
just test              # Flake check + build all hosts

# Step 2: Deploy to single host (safe, test changes)
just zephyr            # Deploy to local host
just nexus             # Deploy to remote host (boot goal)

# Step 3: Verify manually
curl http://127.0.0.1:8080/health

# Step 4: Deploy to all hosts
just deploy            # Deploy to all cluster nodes
```

**Equivalent direct commands** (only if just is unavailable):
```bash
# Step 1: Fast syntax check (5 seconds)
nix flake check

# Step 2: Build validation (1-2 minutes)
nbuild  # Uses nixos-rebuild-safe.sh (auto-pauses mining)

# Step 3: Temporary application (safe, rolls back on reboot)
ntest  # Auto-pauses mining

# Step 4: Verify manually
curl http://127.0.0.1:8080/health

# Step 5: Persistent application
nswitch  # Auto-pauses mining
```

### 2. Service Files Must Be Tracked in Git

**Pattern**: Always `git add` new Python files before rebuilding

**Why**: Nix builds packages from git-tracked files only. Untracked files are excluded.

```bash
# ❌ WRONG - creates file but doesn't add to git
echo "print('hello')" > modules/services/ai-inference/ai_inference_gateway/new_module.py
sudo nixos-rebuild switch --flake .#zephyr  # ERROR: ModuleNotFoundError

# ✅ CORRECT - add to git first
echo "print('hello')" > modules/services/ai-inference/ai_inference_gateway/new_module.py
git add modules/services/ai-inference/ai_inference_gateway/new_module.py
sudo nixos-rebuild switch --flake .#zephyr  # SUCCESS
```

### 3. Environment Variables in Nix Services

**Pattern**: Use `lib.generators.toJSON {}` for complex env vars

**Why**: Nix needs to serialize complex data structures to environment variables.

```nix
# In gateway.nix or configuration.nix
services.ai-inference.mcp = {
  enable = true;
  servers = {
    web-search-prime = {
      url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
      headers = {
        Authorization = "Bearer /run/agenix/zai-api-key";
      };
    };
  };
};

# This becomes:
environment.MCP_SERVERS = lib.generators.toJSON {} cfg.mcp.servers;
# Result: MCP_SERVERS='{"web-search-prime":{"url":"...","headers":{...}}}'
```

### 4. API Key File Paths in Headers

**Pattern**: Store file path in header, read actual key in Python code

**Why**: Agenix deploys secrets to `/run/agenix/`. Services must read these files at runtime.

```nix
# Nix configuration (store path reference)
headers = {
  Authorization = "Bearer /run/agenix/zai-api-key";
};
```

```python
# Python code (read actual key)
if header_value.startswith("Bearer ") and "/run/" in header_value:
    file_path = header_value.split(" ", 1)[1].strip()
    with open(file_path, "r") as f:
        api_key = f.read().strip()
        headers[header_name] = f"Bearer {api_key}"
```

---

## Common Pitfalls

### ❌ Modifying Auto-Generated Files
```bash
# DON'T EDIT THIS - it's regenerated by nixos-generate-config
hardware-configuration.nix
```

**Solution**: Make changes in `configuration.nix` or modules, not in hardware config.

### ❌ Forgetting to Add New Files to Git
```bash
# Created new Python module
touch modules/services/ai-inference/ai_inference_gateway/mcp_broker.py

# Forgot to git add
sudo nixos-rebuild switch  # ERROR: ModuleNotFoundError
```

**Solution**: Always `git add` new files before rebuilding.

### ❌ Using High-Cardinality Labels in Prometheus Metrics
```python
# WRONG - creates unlimited labels
request_duration.labels(model="qwen", backend="http://127.0.0.1:1234").observe(duration)

# CORRECT - uses low-cardinality types
request_duration.labels(model="qwen", backend="lm-studio").observe(duration)
```

**Solution**: Use backend type, not URL.

### ❌ Not Reading API Key Files
```python
# WRONG - uses literal string as auth
headers = {"Authorization": "Bearer /run/agenix/zai-api-key"}

# CORRECT - reads actual key from file
with open("/run/agenix/zai-api-key", "r") as f:
    api_key = f.read().strip()
    headers = {"Authorization": f"Bearer {api_key}"}
```

**Solution**: Always read file contents when header contains file path.

### ❌ Missing Accept Header for ZAI MCP Servers
```python
# WRONG - returns 400 error
headers = {"Content-Type": "application/json"}

# CORRECT - ZAI requires both
headers = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream"
}
```

**Solution**: Always include both Accept types for ZAI MCP calls.

---

## Debugging Workflow

**CRITICAL: Zero Tolerance Policy for Errors**

This project maintains a **zero tolerance policy for errors and bugs**. ANY error encountered during development, building, deployment, or operation MUST be investigated and resolved. Never ignore errors, warnings, or unexpected behavior.

### Core Debugging Principles

1. **Never Ignore Errors**: When ANY error occurs:
   - Build warnings
   - Service failures
   - Journal errors
   - Test failures
   - Unexpected behavior

   **STOP** and investigate immediately. Do not proceed with the assumption that "it's probably fine."

2. **Async Subagent Debugging Pattern**:

   When you encounter an error, launch an async subagent to investigate while you continue with other tasks:

   ```
   Launch Agent(subagent_type="general-purpose" or "Explore",
                prompt="Investigate [specific error]. Find root cause, affected components, and recommend fix.",
                run_in_background=true)
   ```

   The agent will:
   - Search for related errors in logs
   - Check configuration files
   - Trace dependency chains
   - Test potential fixes
   - Report back with findings

3. **During NixOS Rebuilds**:
   - Monitor for warnings/errors in build output
   - Launch async agent to investigate ANY non-success result
   - Don't proceed with deployment until build is clean
   - Verify fixes on all affected nodes

4. **Service Failures**:
   ```bash
   # Immediate triage
   systemctl status <service>
   journalctl -xe

   # Launch async agent for deep investigation
   Agent(subagent_type="general-purpose",
         prompt="Debug <service> failure. Check logs, dependencies, configuration. Find root cause.",
         run_in_background=true)
   ```

5. **Boot-Time Errors**:
   ```bash
   # Check for errors during boot
   journalctl -b 0 --priority=err

   # Launch async agent to investigate
   Agent(subagent_type="Explore",
         prompt="Find all boot errors on [node]. Check service dependencies, cyclic dependencies, missing modules.",
         run_in_background=true)
   ```

6. **Verification After Fixes**:
   - Always verify the fix actually resolved the issue
   - Check for regressions (new errors introduced)
   - Test on all nodes/hosts affected
   - Document root cause and solution

### Service-Specific Debugging

#### 1. Check Service Status
```bash
systemctl status ai-inference-gateway
```

### 2. View Recent Logs
```bash
journalctl -u ai-inference-gateway -n 100 --no-pager
```

### 3. Follow Logs in Real-Time
```bash
journalctl -u ai-inference-gateway -f
```

### 4. Check Configuration
```bash
# Verify service is enabled
systemctl is-enabled ai-inference-gateway

# Check environment variables
systemctl show ai-inference-gateway --property=Environment
```

### 5. Test Manually
```bash
# Health check
curl -v http://127.0.0.1:8080/health

# With verbose output
curl -v -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/qwen3.5-9b","messages":[{"role":"user","content":"Test"}],"max_tokens":10}'
```

---

## Testing MCP Integration

### 1. Direct Server Test (Bypass Gateway)
```bash
# Test ZAI MCP server directly
curl -X POST "https://api.z.ai/api/mcp/web_search_prime/mcp" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list"
  }'
```

### 2. Through Gateway
```bash
# List tools
curl http://127.0.0.1:8080/mcp/tools | jq .

# Call tool
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "web-search-prime",
    "tool": "webSearchPrime",
    "arguments": {"search_query": "NixOS"}
  }' | jq .
```

### 3. Check MCP Server Health
```bash
curl http://127.0.0.1:8080/mcp/health/web-search-prime | jq .
```

---

## Gateway Development Patterns

### Adding New Endpoints

```python
# In modules/services/ai-inference/ai_inference_gateway/main.py

@app.get("/new-endpoint")
async def new_endpoint():
    """Description of what this does."""
    return {"status": "ok", "data": []}

@app.post("/new-endpoint")
async def new_endpoint_post(request: Request):
    """Handle POST requests."""
    body = await request.json()
    # Process body
    return {"result": "processed"}
```

### Adding Configuration

```python
# In modules/services/ai-inference/ai_inference_gateway/config.py

class NewFeatureConfig(BaseModel):
    enabled: bool = Field(default=False)
    setting: str = Field(default="value")

# Add to GatewayConfig
class GatewayConfig(BaseSettings):
    # ... existing fields ...
    new_feature: NewFeatureConfig = Field(default_factory=NewFeatureConfig)
```

```nix
# In hosts/zephyr/configuration.nix or modules/services/ai-inference/gateway.nix
services.ai-inference.newFeature = {
  enable = true;
  setting = "custom-value";
};
```

### Error Handling Pattern

```python
from fastapi import HTTPException
import logging

logger = logging.getLogger(__name__)

@app.post("/endpoint")
async def endpoint(request: Request):
    try:
        # Process request
        result = await process_something()
        return result
    except ValueError as e:
        logger.warning(f"Validation error: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error")
```

---

## Claude Code MCP Integration

### Available MCP Tools

Claude Code can directly call MCP tools without going through the gateway:

```bash
# List all available MCP tools
/mcp

# NixOS MCP (mcp__nixos__nix)
- Search packages, options, programs
- Query flake inputs
- Get package version history

# Serena MCP (semantic coding)
- find_symbol, find_referencing_symbols
- replace_symbol_body, replace_content
- search_for_pattern, get_symbols_overview
```

### Using MCP in Context

```python
# When you need to look up NixOS options
mcp__nixos__nix(action="search", type="options", query="networking")

# When you need to understand code structure
get_symbols_overview(relative_path="modules/services/ai-inference/gateway.nix")

# When you need to find references
find_referencing_symbols(name_path="GatewayConfig", relative_path="modules/services/ai-inference/gateway.nix")
```

---

### Python
- Use `logger.debug()` for debug info, not `logger.info("[DEBUG]")`
- Always guard expensive debug calls: `if logger.isEnabledFor(logging.DEBUG):`
- Use async/await for I/O operations
- Type hints required for function signatures
- Docstrings for all public functions

### Nix
- 2 spaces for indentation
- Comments above settings, not inline
- Use `inherit` where appropriate
- Attribute sets use trailing commas

---

## Profile-Based Host Configuration

Hosts use a **declarative profile system** for composable configuration. This eliminates repetitive setup and makes adding new hosts trivial.

### Defining a Host

```nix
# hosts/<hostname>/configuration.nix
{ lib, pkgs, ... }: {
  imports = [
    ../../modules/default.nix
    ../../modules/common-host.nix
    # ... other imports
  ];

  # Hardware profiles
  hardware.profiles = {
    amd.zen = true;        # Zen CPU optimizations
    nvidia.enable = true;  # NVIDIA GPU
    monitoring.enable = true;
  };

  # Role profiles
  profiles.role = {
    gaming = true;         # Enables gaming services
    mining = true;         # Enables mining services
    aiInference = true;    # Enables AI gateway
  };

  # Network profiles
  profiles.network.tailscale.enable = true;
}
```

### Available Profiles

**Hardware** (`modules/profiles/hardware/`):
| Profile | Description |
|---------|-------------|
| `amd.enable` | AMD CPU IOMMU |
| `amd.zen` | Zen CPU optimizations |
| `intel.enable` | Intel CPU optimizations |
| `nvidia.enable` | NVIDIA GPU support |
| `nvidia.multiGpu` | Multi-GPU CUDA settings |
| `amdgpu.enable` | AMD GPU support |
| `amdgpu.wayland` | ROC_ENABLE_PRE_VEGA |
| `monitoring.enable` | lm-sensors |

**Role** (`modules/profiles/role/`):
| Profile | Description |
|---------|-------------|
| `workstation` | Desktop + development |
| `gaming` | Steam, Lutris |
| `vr` | WiVRn, SteamVR |
| `mining` | GPU/CPU mining |
| `aiInference` | AI gateway + MCP |
| `desktop` | Plasma, Wayland |

**Network** (`modules/profiles/network/`):
| Profile | Description |
|---------|-------------|
| `tailscale.enable` | Enable Tailscale VPN |
| `tailscale.advertiseRoutes` | Routes to advertise |

### Current Hosts

| Host | Hardware | Roles |
|------|----------|-------|
| **zephyr** | amd.zen, nvidia, multiGpu, corsair | workstation, gaming, vr, mining, ai |
| **nexus** | amd.zen, nvidia, multiGpu | gaming, vr, mining, ai |
| **forge** | intel, nvidia, multiGpu, amdgpu | mining, ai |
| **sentry** | amd.zen, amdgpu | mining, ai |

---

## File Organization

```
/etc/nixos/
├── flake.nix                    # Main flake definition
├── flake.lock                   # Auto-generated, DO NOT EDIT
├── AGENTS.md                    # Agent guidelines
├── CLAUDE.md                    # Claude Code specific patterns
├── justfile                     # Just commands
├── hosts/
│   ├── zephyr/
│   │   ├── configuration.nix    # Host-specific config (profiles)
│   │   └── hardware-configuration.nix
│   ├── nexus/
│   ├── forge/
│   └── sentry/
├── lib/
│   ├── attrs.nix                # Attribute utilities
│   └── modules.nix              # Module discovery helpers
├── modules/
│   ├── default.nix              # Module aggregator
│   ├── profiles/                # Profile system
│   │   ├── hardware/            # Hardware profiles (CPU/GPU)
│   │   ├── role/                # Role profiles (gaming, mining, AI)
│   │   └── network/             # Network profiles (tailscale)
│   ├── common-host.nix          # Shared host imports
│   ├── desktop/                 # Desktop modules
│   ├── gaming/                  # Gaming modules
│   ├── hardware/                # Hardware-specific configs
│   ├── mining/                  # Mining modules
│   ├── services/                # Service modules
│   │   └── ai-inference/        # AI gateway
│   └── shell/                   # Shell configuration
└── scripts/
    └── nixos-rebuild-safe.sh    # Rebuild with mining pause
```

---

## Performance Considerations

### Health Check Caching
```python
# Don't check health on every request - use caching
cache_duration = 30  # seconds
if now - last_check > cache_duration:
    is_healthy = await check_backend_health()
```

### Connection Pooling
```python
# Reuse HTTP clients, don't create new ones per request
async with httpx.AsyncClient() as client:
    # Make multiple requests with same client
    response1 = await client.get(url1)
    response2 = await client.get(url2)
```

### Streaming Responses
```python
# For long responses, use streaming
async def stream_response():
    async with httpx.AsyncClient() as client:
        async with client.stream("POST", url, json=data) as response:
            async for chunk in response.aiter_bytes():
                yield chunk
```

---

## Spacebot Integration

Spacebot uses the gateway as an OpenAI-compatible API endpoint:

```bash
# Spacebot configuration
spacebot config set api-base-url http://127.0.0.1:8080
spacebot config set model qwen/qwen3.5-9b

# Spacebot can now make concurrent requests
# Gateway handles load balancing and auto-offload to ZAI
```

**Key Features for Spacebot**:
- ✅ OpenAI-compatible `/v1/chat/completions` endpoint
- ✅ Handles concurrent requests (no concurrency limiter)
- ✅ Auto-offload to ZAI when LM Studio busy
- ✅ Streaming responses supported
- ✅ MCP tools available through `/mcp/*` endpoints

---

## Rollback Procedures

### If Build Fails
```bash
# Check what went wrong
sudo nixos-rebuild build --flake .#zephyr 2>&1 | tee build.log

# Revert problematic changes
git checkout modules/services/ai-inference/ai_inference_gateway/main.py

# Rebuild
sudo nixos-rebuild switch --flake .#zephyr
```

### If Service Won't Start
```bash
# Check logs
journalctl -u ai-inference-gateway -n 200

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Or switch to specific generation
sudo nixos-rebuild switch --list-generations
sudo nixos-rebuild switch --profile /nix/var/nix/profiles/system --switch-generation <number>
```

### If MCP Calls Fail
```bash
# Test direct server connection
curl -X POST "https://api.z.ai/api/mcp/web_search_prime/mcp" \
  -H "Authorization: Bearer $(cat /run/agenix/zai-api-key)" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

# Check gateway logs
journalctl -u ai-inference-gateway -f | grep -i mcp

# Verify MCP configuration
curl http://127.0.0.1:8080/mcp/servers | jq .
```

---

## Monitoring & Metrics

### Prometheus Metrics Endpoint
```bash
# All available metrics
curl http://127.0.0.1:8080/metrics

# Specific metrics
curl -s http://127.0.0.1:8080/metrics | grep ai_inference_request_duration
curl -s http://127.0.0.1:8080/metrics | grep ai_inference_total_tokens
```

### Health Check
```bash
# Overall health
curl http://127.0.0.1:8080/health | jq .

# Backend health only
curl http://127.0.0.1:8080/health | jq .backend.healthy
```

### Request Metadata
```bash
# Gateway adds metadata to responses
curl -s -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/qwen3.5-9b","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' \
  | jq .gateway_metadata
```

---

## Best Practices Summary

**Zero Tolerance for Errors (CRITICAL)**:
1. **Never ignore errors or warnings**: Debug ANY error immediately using async subagents
2. **Launch async agents for debugging**: Investigate errors in parallel while continuing work
3. **Verify all fixes**: Ensure errors are actually resolved and no regressions introduced
4. **Test on all affected nodes**: Don't assume a fix on one node applies everywhere

**Development Workflow**:
5. **Always test incrementally**: `flake check` → `build` → `test` → `switch`
6. **Track all new files in git**: Nix only packages git-tracked files
7. **Read API key files at runtime**: Don't use literal file paths as credentials
8. **Use low-cardinality labels**: Backend type, not URL, for Prometheus metrics
9. **Cache expensive operations**: Health checks, DNS lookups, etc.
10. **Handle SSE responses**: ZAI MCP servers use Server-Sent Events format
11. **Include proper Accept headers**: `application/json, text/event-stream` for ZAI
12. **Use logger.debug() not logger.info("[DEBUG])**: Prevent log spam
13. **Test MCP servers directly first**: Bypass gateway to isolate issues
14. **Check logs immediately after errors**: `journalctl -u ai-inference-gateway -n 100`

---

## Additional Resources

- **AGENTS.md**: MCP protocol details and server configuration
- **README.md** (modules/services/ai-inference/): Gateway documentation
- **gateway-improvement-roadmap.md**: Planned improvements and todos
- **NixOS Manual**: https://nixos.org/manual/nixos/stable/
- **FastAPI Docs**: https://fastapi.tiangolo.com/
