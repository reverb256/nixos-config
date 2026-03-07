# NixOS Configuration - Agent Guidelines

## Project Overview
This is a NixOS flake-based system configuration managing a 4-host Linux cluster. All system configurations are declarative and managed through Nix modules with a profile-based architecture for composable, reusable configurations.

---

## Build & Test Commands

### Essential Commands
```bash
# Fast syntax check (5 seconds) - ALWAYS RUN FIRST
nix flake check

# Build without applying (1-2 minutes)
sudo nixos-rebuild build --flake .#zephyr

# Test configuration (applies changes, rollback on reboot)
sudo nixos-rebuild test --flake .#zephyr

# Switch to new configuration (persist across reboots)
sudo nixos-rebuild switch --flake .#zephyr

# Update all flake inputs
nix flake update
```

### Fish Aliases (auto-pause mining)
```bash
nswitch      # nixos-rebuild switch
nswitchu     # switch with --upgrade
ntest        # nixos-rebuild test
nbuild       # nixos-rebuild build
ndry         # nixos-rebuild dry-activate
```

### Justfile Recipes
```bash
just switch          # Local switch (auto-pauses mining)
just test            # Test configuration (flake check + colmena build)
just deploy          # Deploy to all hosts
just zephyr          # Deploy to zephyr only
just nexus           # Deploy to nexus only
just forge           # Deploy to forge only
just sentry          # Deploy to sentry only
```

### Safe Rebuild Script
```bash
# Auto-pauses mining, runs rebuild, restarts mining
sudo /etc/nixos/scripts/nixos-rebuild-safe.sh switch --flake .#zephyr
```

### Testing Strategy
1. Always run `nix flake check` first for syntax validation
2. Use `nixos-rebuild build` to verify configuration compiles
3. Use `nixos-rebuild test` for temporary changes (rollback safe)
4. Only use `switch` for verified, production-ready changes

---

## Code Style Guidelines

### Nix Language Conventions
- **2 spaces** for indentation (no tabs)
- Blank lines between major sections
- Comments use `#` prefix, place above setting not inline
- Use trailing commas for multi-line attribute sets

### Attribute Sets & Lists
```nix
{ config, pkgs, inputs, ... }:  # Use ellipsis pattern
{
  description = "NixOS configuration";
  inputs = { inherit nixpkgs home-manager; };  # Use inherit
};
```

### Lists
```nix
environment.systemPackages = with pkgs; [
  tmux
  mosh
  tailscale
  inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
];
```

---

## Project Structure

### Flake Outputs
```
outputs:
├── nixosConfigurations  # For local nixos-rebuild
├── colmena              # Raw hive configuration
├── colmenaHive          # Wrapped hive for multi-host deployment
├── packages             # Custom packages (claude)
├── overlays             # Package overlays
└── apps                 # Colmena app
```

### Directory Structure
```
/etc/nixos/
├── flake.nix                    # Main flake definition
├── flake.lock                   # Auto-generated, DO NOT EDIT
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
│   └── shell/                   # Shell configuration
├── scripts/
│   └── nixos-rebuild-safe.sh    # Rebuild with mining pause
└── secrets/
    └── *.age                    # Agenix encrypted secrets
```

### Files
- **flake.nix**: Inputs and outputs (EDIT THIS)
- **configuration.nix**: Legacy main config (use host-specific configs)
- **hardware-configuration.nix**: Auto-generated per host (DO NOT EDIT)
- **flake.lock**: Reproducibility lockfile (AUTO-GENERATED, DO NOT EDIT)

---

## Profile System

Hosts use a declarative profile system for composable configuration:

### Hardware Profiles
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

### Role Profiles
| Profile | Description |
|---------|-------------|
| `workstation` | Desktop + development |
| `gaming` | Steam, Lutris |
| `vr` | WiVRn, SteamVR |
| `mining` | GPU/CPU mining |
| `aiInference` | AI gateway + MCP |
| `desktop` | Plasma, Wayland |

### Network Profiles
| Profile | Description |
|---------|-------------|
| `tailscale.enable` | Enable Tailscale VPN |
| `tailscale.advertiseRoutes` | Routes to advertise |

### Host Definitions
```nix
# Example: hosts/zephyr/configuration.nix
{ lib, pkgs, ... }: {
  imports = [
    ../../modules/default.nix
    ../../modules/common-host.nix
  ];

  # Hardware profiles
  hardware.profiles = {
    amd.zen = true;
    nvidia.enable = true;
    nvidia.multiGpu = true;
    corsair.enable = true;
    monitoring.enable = true;
  };

  # Role profiles
  profiles.role = {
    workstation = true;
    gaming = true;
    vr = true;
    mining = true;
    aiInference = true;
  };

  # Network profiles
  profiles.network.tailscale.enable = true;
};
```

---

## Hosts

| Host | Hardware | Roles |
|------|----------|-------|
| **zephyr** | AMD Zen, NVIDIA multi-GPU (RTX 3090 + 3060 Ti), Corsair AIO+RGB | workstation, gaming, VR, mining, AI |
| **nexus** | AMD Zen, NVIDIA multi-GPU (2x RTX 3060 Ti) | gaming, VR, mining, AI |
| **forge** | Intel Skylake, NVIDIA multi-GPU (2x RTX 4060), AMD GPU | mining, AI |
| **sentry** | AMD Zen, AMD GPU (Wayland) | mining, AI |

---

## Naming Conventions
- Hostnames: lowercase (e.g., `zephyr`)
- Usernames: underscores for spaces (e.g., `j_kro`)
- Flake inputs: lowercase with hyphens (e.g., `zen-browser`)
- Service names: match systemd services (e.g., `tailscale`, `networkmanager`)
- Profiles: camelCase for nested (e.g., `amd.zen`, `profiles.role`)

---

## Formatting
```bash
# Format all .nix files
nix-shell -p nixpkgs-fmt --run "nixpkgs-fmt **/*.nix"

# Format specific files
nixpkgs-fmt flake.nix configuration.nix
```

---

## Common Patterns
```nix
# Enable services
services.xserver.enable = true;
services.desktopManager.plasma6.enable = true;

# System packages
environment.systemPackages = with pkgs; [ package1 package2 ];

# User config
users.users.j_kro = {
  isNormalUser = true;
  description = "Jeremy Kroeker";
  shell = pkgs.fish;
  extraGroups = [ "networkmanager" "wheel" ];
};

# Home Manager
home-manager.users.j_kro = { pkgs, lib, ... }: {
  home.stateVersion = "26.05";
};
```

---

## Important Notes
- Keep `system.stateVersion` and `home.stateVersion` current
- Never edit `hardware-configuration.nix` - regenerate with `nixos-generate-config`
- Run `nix flake update` before making changes
- Check `nix flake show` for available configurations
- Build/test/switch require root/sudo
- All new Python files MUST be added to git before rebuilding (Nix only packages git-tracked files)

---

## Multi-Host Deployment (Colmena)

### Colmena Commands
```bash
# Build all hosts (dry run)
nix run .#apps.x86_64-linux.colmena -- build

# Apply to specific host
nix run .#apps.x86_64-linux.colmena -- apply --on zephyr

# Apply to remote hosts (use 'boot' goal to avoid inhibitors)
nix run .#apps.x86_64-linux.colmena -- apply --on nexus,forge,sentry boot

# Deploy to all hosts
just deploy
```

### Remote Deployment Notes
- Remote hosts use `boot` goal to avoid switch inhibitors (e.g., dbus changes)
- Local host (zephyr) uses `switch` goal
- Mining auto-pauses on all hosts during deployment

---

## MCP (Model Context Protocol) Integration

### Overview
The AI inference gateway includes an MCP broker that aggregates tools from multiple MCP servers, enabling AI agents to call external tools through the gateway.

### MCP Server Configuration
MCP servers are configured in `.mcp.json`:

```json
{
  "mcpServers": {
    "web-search-prime": {
      "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
      "headers": {
        "Authorization": "Bearer /run/agenix/zai-api-key"
      }
    }
  }
}
```

### Key Implementation Insights

**1. MCP Protocol Structure**
- Uses JSON-RPC 2.0 format over HTTP/SSE
- Methods: `initialize`, `tools/list`, `tools/call`
- Responses come in Server-Sent Events (SSE) format
- Requires specific `Accept` header: `application/json, text/event-stream`

**2. Authentication Pattern**
```python
# Headers with file paths need special handling
"Authorization": "Bearer /run/agenix/zai-api-key"

# Python code to load actual key:
if header_value.startswith("Bearer "):
    file_path = header_value.split(" ", 1)[1].strip()
    with open(file_path, "r") as f:
        api_key = f.read().strip()
        headers[header_name] = f"Bearer {api_key}"
```

**3. SSE Response Parsing**
```python
# ZAI MCP servers return SSE format:
# id:1
# event:message
# data:{"jsonrpc":"2.0","id":1,"result":{...}}

# Parse SSE:
async for line in response.aiter_lines():
    if line.startswith("data:"):
        data = json.loads(line[5:].strip())
        # Handle data["result"] or data["error"]
```

**4. Tool Name Discovery**
- Tool names are **case-sensitive** (e.g., `webSearchPrime` not `web_search`)
- Always fetch tool names via `tools/list` before calling
- Different servers may have different tool names for similar functionality

**5. Accept Header Requirements**
```python
headers = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream"  # Required by ZAI MCP servers
}
```

### MCP Endpoints
```
GET  /mcp/servers              # List configured MCP servers with health status
GET  /mcp/tools               # List available tools from all servers
POST /mcp/call                # Call an MCP tool
GET  /mcp/health/{server_name}  # Check MCP server health
```

### Testing MCP Integration

**Direct Server Test:**
```bash
curl -X POST "https://api.z.ai/api/mcp/web_search_prime/mcp" \
  -H "Authorization: Bearer YOUR_KEY" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list"
  }'
```

**Through Gateway:**
```bash
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{
    "server": "web-search-prime",
    "tool": "webSearchPrime",
    "arguments": {"search_query": "test"}
  }'
```

### Common Pitfalls

**❌ Wrong Tool Name**
```json
{"tool": "web_search"}  // 404 Not Found
```

**✅ Correct Tool Name**
```json
{"tool": "webSearchPrime"}  // Works!
```

**❌ Missing Accept Header**
```bash
# Returns: "Accept header must include both application/json and text/event-stream"
curl -H "Accept: application/json" ...
```

**✅ Correct Accept Header**
```bash
curl -H "Accept: application/json, text/event-stream" ...
```

**❌ Not Reading API Key File**
```python
headers = {"Authorization": "Bearer /run/agenix/zai-api-key"}  # Literal string
```

**✅ Reading API Key from File**
```python
# Extract file path and read contents
if "/run/" in header_value:
    with open(file_path, "r") as f:
        api_key = f.read().strip()
    headers = {"Authorization": f"Bearer {api_key}"}
```

### ZAI MCP Servers

| Server | URL | Tool Names | Purpose |
|--------|-----|------------|---------|
| web-search-prime | `/api/mcp/web_search_prime/mcp` | `webSearchPrime` | Web search |
| web-reader | `/api/mcp/web_reader/mcp` | `webReader` | URL content fetching |
| zread | `/api/mcp/zread/mcp` | `get_repo_structure`, `read_file` | GitHub analysis |
| 4-5v-mcp-server | `/api/mcp/4_5v/mcp` | `analyze_image` | Image analysis |

### Debugging Tips

1. **Test Directly First**: Always test MCP servers directly before testing through gateway
2. **Check Response Format**: Use `curl -v` to see actual response headers and format
3. **Enable Debug Logging**: Set `LOG_LEVEL=DEBUG` in environment for verbose logs
4. **Verify File Permissions**: Ensure service user can read agenix secret files
5. **Test JSON-RPC Methods**: Try `initialize` → `tools/list` → `tools/call` in order

---

## Service Management

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

---

## Gateway Testing

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
```
