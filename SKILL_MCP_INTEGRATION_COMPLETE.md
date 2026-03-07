# Claude Code Skills → OpenCode Integration

## Summary

Successfully converted Claude Code skills to MCP servers for OpenCode integration through the AI gateway.

## What Was Implemented

### 1. MCP Servers Created

#### nix-rebuild MCP Server (`/etc/nixos/skills/nix-rebuild-mcp/`)
**Purpose**: Safe NixOS rebuilding workflow

**Tools**:
- `nix_flake_check` - Fast syntax validation (~5s)
- `nixos_rebuild_build` - Build without applying (1-2min)
- `nixos_rebuild_test` - Test temporarily (rollback safe)
- `nixos_rebuild_switch` - Apply persistently
- `nix_flake_update` - Update flake inputs

**Files**:
- `server.py` - MCP server implementation (284 lines)
- `README.md` - Usage documentation

#### add-service MCP Server (`/etc/nixos/skills/add-service-mcp/`)
**Purpose**: Create systemd service modules

**Tools**:
- `create_service_module` - Generate service template
- `register_module` - Add to modules/default.nix
- `enable_service` - Enable on host config
- `get_service_template` - Get template reference

**Files**:
- `server.py` - MCP server implementation (318 lines)
- `README.md` - Usage documentation

### 2. Configuration Updated

**File**: `/etc/nixos/hosts/zephyr/configuration.nix`

Added MCP server registrations with Python environment including MCP SDK:

```nix
nix-rebuild = {
  type = "local";
  command = ["${(pkgs.python3.withPackages (ps: [ ps.mcp ])).interpreter}" ...];
  environment = { NIX_HOST = "zephyr"; };
  enabled = true;
};

add-service = {
  type = "local";
  command = ["${(pkgs.python3.withPackages (ps: [ ps.mcp ])).interpreter}" ...];
  environment = { };
  enabled = true;
};
```

### 3. Documentation Created

**File**: `/etc/nixos/docs/skills-to-mcp-integration.md`

Comprehensive guide covering:
- Architecture overview
- Deployment steps
- Testing procedures
- Creating new skill MCP servers
- Troubleshooting

## How It Works

```
Claude Code Skill (.claude/skills/*/SKILL.md)
         ↓ Manual conversion
MCP Server (skills/*-mcp/server.py)
         ↓ Registered in config
AI Gateway MCP Broker (port 8080)
         ↓ HTTP API
OpenCode Discovery & Tool Calling
```

## Deployment Required

The configuration has been updated but **not yet applied**. To activate:

```bash
# 1. Validate syntax
cd /etc/nixos
nix flake check

# 2. Build (test without applying)
sudo nixos-rebuild build --flake .#zephyr

# 3. Test temporarily (rollback on reboot)
sudo nixos-rebuild test --flake .#zephyr

# 4. Verify MCP servers
curl http://127.0.0.1:8080/mcp/servers | jq '.servers[] | select(.name | contains("nix") or contains("add"))'

# 5. Apply permanently (if satisfied)
sudo nixos-rebuild switch --flake .#zephyr
```

## Testing After Deployment

### Via Gateway API

```bash
# List all MCP servers (should include nix-rebuild and add-service)
curl http://127.0.0.1:8080/mcp/servers

# List available tools
curl http://127.0.0.1:8080/mcp/tools

# Call nix-rebuild tool
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "nix-rebuild",
    "tool": "nix_flake_check",
    "arguments": {}
  }'

# Call add-service tool
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "add-service",
    "tool": "get_service_template",
    "arguments": {}
  }'
```

### Via OpenCode

OpenCode will automatically discover the tools through the gateway. No manual configuration needed.

## Benefits

1. ✅ **Skill Reuse**: Claude Code skills now work with OpenCode
2. ✅ **Tool Discovery**: Automatic tool discovery via gateway
3. ✅ **Unified API**: Single HTTP endpoint for all tools
4. ✅ **Type Safety**: JSON Schema validation for tool arguments
5. ✅ **Error Handling**: Consistent error responses across tools
6. ✅ **Documentation**: Self-documenting tools via MCP protocol

## Architecture

### Components

1. **MCP Server** (Python)
   - Implements MCP protocol
   - Exposes skill functionality as tools
   - Runs as stdio process

2. **AI Gateway** (NixOS service)
   - MCP broker aggregates servers
   - HTTP API on port 8080
   - Manages server lifecycle

3. **OpenCode** (Client)
   - Discovers tools via `/mcp/tools`
   - Calls tools via `/mcp/call`
   - No MCP server management needed

### Data Flow

```
OpenCode Request → Gateway HTTP API → MCP Broker → Local MCP Server → Tool Execution
                                                       ↓
OpenCode Response ← Gateway HTTP API ← MCP Broker ← JSON Result
```

## Files Modified

```
/etc/nixos/
├── hosts/zephyr/configuration.nix         # Added MCP server registrations
├── skills/
│   ├── nix-rebuild-mcp/
│   │   ├── server.py                      # NEW: MCP server implementation
│   │   └── README.md                      # NEW: Usage documentation
│   └── add-service-mcp/
│       ├── server.py                      # NEW: MCP server implementation
│       └── README.md                      # NEW: Usage documentation
└── docs/
    └── skills-to-mcp-integration.md       # NEW: Integration guide
```

## Next Steps

1. **Deploy**: Run deployment commands above
2. **Verify**: Check tools appear in OpenCode
3. **Test**: Use tools from OpenCode
4. **Extend**: Convert more skills using the documented pattern

## Troubleshooting

### MCP Server Not Appearing

```bash
# Check if gateway is running
systemctl status ai-inference-gateway

# Check gateway logs
journalctl -u ai-inference-gateway -f

# Verify configuration
nixos-rebuild build --flake .#zephyr
```

### Tool Call Failing

```bash
# Test server directly
nix-shell -p "python3.withPackages (ps: [ ps.mcp ])" --run \
  "python3 /etc/nixos/skills/nix-rebuild-mcp/server.py"

# Check server logs
journalctl -u ai-inference-gateway | grep nix-rebuild
```

## Status

✅ **COMPLETE** - Ready for deployment

All tasks completed:
- [x] Analyzed existing skills
- [x] Created nix-rebuild MCP server
- [x] Created add-service MCP server
- [x] Configured Python environment with MCP SDK
- [x] Registered servers in gateway configuration
- [x] Tested MCP servers directly
- [x] Verified OpenCode integration path
- [x] Created comprehensive documentation
