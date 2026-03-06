# nix-rebuild MCP Server

MCP server providing tools for safe NixOS rebuilding workflow.

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
    nix-rebuild = {
      type = "local";
      command = [pkgs.python3.pkgs.mcp "/bin/python", "/etc/nixos/skills/nix-rebuild-mcp/server.py"];
      environment = {
        NIX_HOST = "zephyr";
      };
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
| `nix_flake_check` | Run nix flake check (fast syntax validation, ~5 seconds) |
| `nixos_rebuild_build` | Build without applying (1-2 minutes, validates only) |
| `nixos_rebuild_test` | Test temporarily (applies, rolls back on reboot) |
| `nixos_rebuild_switch` | Switch persistently (survives reboots) |
| `nix_flake_update` | Update all flake inputs |

## Usage via OpenCode

```bash
# List available tools
curl http://127.0.0.1:8080/mcp/tools?server=nix-rebuild

# Call tool via gateway
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "nix-rebuild",
    "tool": "nix_flake_check",
    "arguments": {}
  }'

# Build configuration
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "nix-rebuild",
    "tool": "nixos_rebuild_build",
    "arguments": {"hostname": "zephyr"}
  }'
```

## Workflow

1. **Check syntax**: `nix_flake_check`
2. **Build**: `nixos_rebuild_build`
3. **Test**: `nixos_rebuild_test` (optional, safe)
4. **Switch**: `nixos_rebuild_switch` (persistent)
