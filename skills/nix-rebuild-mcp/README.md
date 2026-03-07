# nix-rebuild MCP Server

MCP server providing tools for safe NixOS rebuilding workflow with automatic mining pause.

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
nswitch  # Uses nixos-rebuild-safe.sh (auto-pauses mining)
```

## Available Tools

| Tool | Description |
|-------|-------------|
| `nix_flake_check` | Run nix flake check (fast syntax validation, ~5 seconds) |
| `nixos_rebuild_build` | Build without applying (1-2 minutes, validates only) |
| `nixos_rebuild_test` | Test temporarily (applies, rolls back on reboot) |
| `nixos_rebuild_switch` | Switch persistently (survives reboots) |
| `nixos_rebuild_safe_switch` | Switch with mining auto-pause (recommended) |
| `nix_flake_update` | Update all flake inputs |

## Usage via Gateway

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

# Safe switch with mining pause
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "nix-rebuild",
    "tool": "nixos_rebuild_safe_switch",
    "arguments": {"hostname": "zephyr"}
  }'
```

## Command Aliases

The system provides fish aliases for quick access:

```bash
nswitch      # nixos-rebuild switch (auto-pauses mining)
nswitchu     # switch with --upgrade
ntest        # nixos-rebuild test
nbuild       # nixos-rebuild build
ndry         # nixos-rebuild dry-activate
```

## Justfile Recipes

```bash
just switch          # Local switch (auto-pauses mining)
just test            # Test configuration
just deploy          # Deploy to all hosts
just zephyr          # Deploy to zephyr only
just nexus           # Deploy to nexus only
just forge           # Deploy to forge only
just sentry          # Deploy to sentry only
```

## Workflow

1. **Check syntax**: `nix_flake_check` (~5 seconds)
2. **Build**: `nixos_rebuild_build` (1-2 minutes, auto-pauses mining)
3. **Test** (optional): `nixos_rebuild_test` (safe, rolls back on reboot)
4. **Switch**: `nixos_rebuild_safe_switch` (auto-pauses mining, persists)

## Mining Auto-Pause

All rebuild commands automatically pause mining to maximize build performance:

```bash
# The nixos-rebuild-safe.sh script:
# 1. Stops xmrig@* and lolminer-* services
# 2. Runs the nixos-rebuild command
# 3. Automatically restarts mining (even if build fails)
```

## Supported Hosts

| Host | Description |
|------|-------------|
| `zephyr` | Main workstation (AMD Zen, NVIDIA multi-GPU) |
| `nexus` | Gaming/mining (AMD Zen, NVIDIA multi-GPU) |
| `forge` | Mining/AI (Intel, NVIDIA + AMD GPU) |
| `sentry` | Mining/AI (AMD Zen, AMD GPU) |
