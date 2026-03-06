# add-service MCP Server

MCP server providing tools for creating systemd service modules.

## Installation

### 1. Install Dependencies

```bash
pip install mcp
```

### 2. Register with AI Gateway

Add to `hosts/zephyr/configuration.nix`:

```nix
services.ai-inference.mcp = {
  enable = true;
  servers = {
    add-service = {
      type = "local";
      command = [pkgs.python3.pkgs.mcp "/bin/python", "/etc/nixos/skills/add-service-mcp/server.py"];
      environment = {};
    };
    # ... other servers
  };
};
```

### 3. Rebuild

```bash
nix flake check
sudo nixos-rebuild switch --flake .#zephyr
```

## Available Tools

| Tool | Description |
|-------|-------------|
| `create_service_module` | Create a new systemd service module at modules/services/ |
| `register_module` | Register service module in modules/default.nix imports |
| `enable_service` | Enable service on host configuration file |
| `get_service_template` | Get systemd service module template for reference |

## Usage via OpenCode

```bash
# List available tools
curl http://127.0.0.1:8080/mcp/tools?server=add-service

# Get template
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "add-service",
    "tool": "get_service_template",
    "arguments": {}
  }'

# Create service
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "add-service",
    "tool": "create_service_module",
    "arguments": {
      "service_name": "my-web-service",
      "description": "Web API server for my app"
    }
  }'

# Register module
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "add-service",
    "tool": "register_module",
    "arguments": {
      "service_name": "my-web-service"
    }
  }'

# Enable on host
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "add-service",
    "tool": "enable_service",
    "arguments": {
      "service_name": "my-web-service",
      "hostname": "zephyr"
    }
  }'
```

## Workflow

1. **Create module**: `create_service_module` (generates template)
2. **Customize**: Edit generated module as needed
3. **Register**: `register_module` (add to modules/default.nix)
4. **Enable**: `enable_service` (add to host config)
5. **Rebuild**: `nix flake check && sudo nixos-rebuild switch`
