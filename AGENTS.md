# NixOS Configuration - Agent Guidelines

## Project Overview
This is a NixOS flake-based system configuration for host "zephyr" running Plasma 6 desktop.
All system configurations are declarative and managed through Nix modules.

---

## Build & Test Commands

### Essential Commands
```bash
# Build configuration (dry-run, no system modification)
sudo nixos-rebuild build --flake .#zephyr

# Test configuration (applies changes, rollback on next boot)
sudo nixos-rebuild test --flake .#zephyr

# Switch to new configuration (persist across reboots)
sudo nixos-rebuild switch --flake .#zephyr

# Update all flake inputs
nix flake update

# Check configuration syntax (no build)
nix flake check
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

### Files
- **flake.nix**: Inputs and outputs (EDIT THIS)
- **configuration.nix**: Main system config (EDIT THIS)
- **hardware-configuration.nix**: Auto-generated (DO NOT EDIT)
- **flake.lock**: Reproducibility lockfile (AUTO-GENERATED, DO NOT EDIT)

### Adding Configurations
- System settings → `configuration.nix`
- User settings → `home-manager.users.j_kro` block
- New flake inputs → `inputs` in flake.nix, pass via `specialArgs`

---

## Naming Conventions
- Hostnames: lowercase (e.g., `zephyr`)
- Usernames: underscores for spaces (e.g., `j_kro`)
- Flake inputs: lowercase with hyphens (e.g., `zen-browser`)
- Service names: match systemd services (e.g., `tailscale`, `networkmanager`)

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

---

## MCP (Model Context Protocol) Integration

### Overview
The AI inference gateway includes an MCP broker that aggregates tools from multiple MCP servers, enabling AI agents to call external tools through the gateway.

### MCP Server Configuration
MCP servers are configured in `configuration.nix` under `services.ai-inference.mcp`:

```nix
services.ai-inference.mcp = {
  enable = true;
  servers = {
    web-search-prime = {
      url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
      headers = {
        Authorization = "Bearer /run/agenix/zai-api-key";
      };
    };
    # Add more servers...
  };
};
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
| web-reader | `/api/mcp/web_reader/mcp` | `fetch_url` | URL content fetching |
| zread | `/api/mcp/zread/mcp` | `github_repo`, `github_file` | GitHub analysis |
| 4-5v-mcp-server | `/api/mcp/4_5v/mcp` | `analyze_image` | Image analysis |

### Debugging Tips

1. **Test Directly First**: Always test MCP servers directly before testing through gateway
2. **Check Response Format**: Use `curl -v` to see actual response headers and format
3. **Enable Debug Logging**: Set `LOG_LEVEL=DEBUG` in environment for verbose logs
4. **Verify File Permissions**: Ensure service user can read agenix secret files
5. **Test JSON-RPC Methods**: Try `initialize` → `tools/list` → `tools/call` in order
