# Claude Code Skills to MCP Integration Guide

## Overview

This document describes how to convert Claude Code skills to MCP (Model Context Protocol) servers for use with OpenCode and other AI systems.

## What Was Done

### 1. Created MCP Servers for Existing Skills

Two MCP servers were created from existing Claude Code skills:

#### nix-rebuild MCP Server
- **Location**: `/etc/nixos/skills/nix-rebuild-mcp/`
- **Tools Provided**:
  - `nix_flake_check` - Fast syntax validation (~5 seconds)
  - `nixos_rebuild_build` - Build without applying (1-2 minutes)
  - `nixos_rebuild_test` - Test temporarily (rollback on reboot)
  - `nixos_rebuild_switch` - Apply persistently
  - `nix_flake_update` - Update flake inputs

#### add-service MCP Server
- **Location**: `/etc/nixos/skills/add-service-mcp/`
- **Tools Provided**:
  - `create_service_module` - Generate service module template
  - `register_module` - Add to modules/default.nix imports
  - `enable_service` - Enable on host configuration
  - `get_service_template` - Get template for reference

### 2. Registered in AI Gateway

Added MCP server configuration to `/etc/nixos/hosts/zephyr/configuration.nix`:

```nix
services.ai-inference.mcp = {
  enable = true;
  servers = {
    # ... existing remote servers ...

    # NixOS Skills MCP Servers
    nix-rebuild = {
      type = "local";
      command = [
        "${(pkgs.python3.withPackages (ps: [ ps.mcp ])).interpreter}"
        "/etc/nixos/skills/nix-rebuild-mcp/server.py"
      ];
      environment = { NIX_HOST = "zephyr"; };
      enabled = true;
    };

    add-service = {
      type = "local";
      command = [
        "${(pkgs.python3.withPackages (ps: [ ps.mcp ])).interpreter}"
        "/etc/nixos/skills/add-service-mcp/server.py"
      ];
      environment = { };
      enabled = true;
    };
  };
};
```

## Architecture

```
Claude Code Skill (SKILL.md)
         ↓
    Parse & Extract
         ↓
   MCP Server (Python)
         ↓
  AI Gateway (MCP Broker)
         ↓
    OpenCode/Other AIs
```

### Key Components

1. **Skill Definition** (SKILL.md)
   - YAML frontmatter with name/description
   - Markdown with workflows and templates

2. **MCP Server** (server.py)
   - Python implementation using MCP SDK
   - Exposes skill functionality as tools
   - Handles stdio communication

3. **AI Gateway** (MCP Broker)
   - Aggregates multiple MCP servers
   - Provides unified HTTP API
   - Manages server lifecycle

4. **OpenCode**
   - Discovers tools via gateway
   - Calls tools through unified API
   - No need for direct MCP server management

## Deployment Steps

### 1. Validate Configuration

```bash
cd /etc/nixos
nix flake check
```

### 2. Build and Test

```bash
# Build (doesn't apply changes)
sudo nixos-rebuild build --flake .#zephyr

# Test (temporary, rollback on reboot)
sudo nixos-rebuild test --flake .#zephyr
```

### 3. Verify MCP Servers

```bash
# Check gateway health
curl http://127.0.0.1:8080/health

# List MCP servers
curl http://127.0.0.1:8080/mcp/servers

# List available tools
curl http://127.0.0.1:8080/mcp/tools
```

### 4. Apply Permanently

```bash
sudo nixos-rebuild switch --flake .#zephyr
```

## Testing MCP Tools

### Direct Server Test

```bash
# Test nix-rebuild server directly
nix-shell -p "python3.withPackages (ps: [ ps.mcp ])" --run \
  "python3 /etc/nixos/skills/nix-rebuild-mcp/server.py" <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
EOF
```

### Via Gateway

```bash
# List tools for specific server
curl "http://127.0.0.1:8080/mcp/tools?server=nix-rebuild"

# Call a tool
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "nix-rebuild",
    "tool": "nix_flake_check",
    "arguments": {}
  }'
```

### Via OpenCode

OpenCode will automatically discover the tools through the gateway. You can use them directly:

```
User: "Run a flake check"
AI: [Calls nix_flake_check tool via gateway]
```

## Creating New Skill MCP Servers

### 1. Create Skill Definition

Create `/etc/nixos/.claude/skills/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: Description of what this skill does
---

# Workflow

1. Step one
2. Step two
3. Step three

# Templates

...
```

### 2. Create MCP Server

Create `/etc/nixos/skills/my-skill-mcp/server.py`:

```python
import asyncio
import json
from mcp.server import Server
from mcp.types import Tool, TextContent
import mcp.server.stdio

server = Server("my-skill-mcp")

@server.list_tools()
async def list_tools():
    return [
        Tool(
            name="my_tool",
            description="What this tool does",
            inputSchema={
                "type": "object",
                "properties": {
                    "param": {
                        "type": "string",
                        "description": "Parameter description"
                    }
                },
                "required": ["param"]
            }
        )
    ]

@server.call_tool()
async def handle_tool_call(name: str, arguments: dict):
    if name == "my_tool":
        # Implement tool logic
        result = {"success": True, "data": "result"}
        return [TextContent(type="text", text=json.dumps(result))]

async def main():
    async with mcp.server.stdio.stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())

if __name__ == "__main__":
    asyncio.run(main())
```

### 3. Register in Configuration

Add to `/etc/nixos/hosts/zephyr/configuration.nix`:

```nix
services.ai-inference.mcp.servers.my-skill = {
  type = "local";
  command = [
    "${(pkgs.python3.withPackages (ps: [ ps.mcp ])).interpreter}"
    "/etc/nixos/skills/my-skill-mcp/server.py"
  ];
  environment = { };
  enabled = true;
};
```

### 4. Test and Deploy

```bash
# Test server directly
nix-shell -p "python3.withPackages (ps: [ ps.mcp ])" --run \
  "python3 /etc/nixos/skills/my-skill-mcp/server.py"

# Validate configuration
nix flake check

# Apply changes
sudo nixos-rebuild switch --flake .#zephyr
```

## Benefits

1. **Skill Reuse**: Skills work with both Claude Code and OpenCode
2. **Tool Discovery**: OpenCode automatically discovers available tools
3. **Unified API**: Single HTTP endpoint for all tools
4. **Type Safety**: JSON Schema validation for tool arguments
5. **Error Handling**: Consistent error responses across all tools

## Limitations

1. **Stateless**: MCP servers are stateless (each call is independent)
2. **Local Only**: Local MCP servers only work on the host they're defined on
3. **Python Required**: Current implementation uses Python MCP SDK
4. **Manual Registration**: Each skill must be registered in configuration

## Future Improvements

1. **Auto-discovery**: Automatically detect and register skill MCP servers
2. **Skill Hot-reload**: Update skills without rebuilding NixOS
3. **Multi-language Support**: Support MCP servers in other languages
4. **Skill Packaging**: Package skills as Nix flakes for easy distribution
5. **Testing Framework**: Automated testing for skill MCP servers

## Troubleshooting

### MCP Server Not Starting

```bash
# Check if MCP package is available
nix-shell -p "python3.withPackages (ps: [ ps.mcp ])" --run "python3 -c 'import mcp'"

# Test server manually
nix-shell -p "python3.withPackages (ps: [ ps.mcp ])" --run \
  "python3 /etc/nixos/skills/my-skill-mcp/server.py"
```

### Tool Not Appearing in Gateway

```bash
# Check gateway logs
journalctl -u ai-inference-gateway -f

# Verify configuration
nixos-rebuild build --flake .#zephyr

# Check server registration
curl http://127.0.0.1:8080/mcp/servers
```

### Tool Call Failing

```bash
# Check tool arguments
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{"server":"my-skill","tool":"my_tool","arguments":{"param":"value"}}'

# Check server logs
journalctl -u ai-inference-gateway | grep my-skill
```

## Related Documentation

- [MCP Specification](https://modelcontextprotocol.io/)
- [AI Gateway Configuration](../modules/services/ai-inference/README.md)
- [Claude Code Skills](../.claude/skills/)
- [OpenCode Configuration](~/.config/opencode/opencode.json)
