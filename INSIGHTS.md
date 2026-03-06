# NixOS Configuration Insights

Key learnings from maintaining this NixOS configuration.

## Code Cleanup (2026-03-06)

### Orphan Detection Pattern
When checking for unused modules, verify across multiple locations:
1. `modules/default.nix` - Global module imports
2. `modules/common-host.nix` - Used by multiple hosts
3. Individual host configs - `hosts/*/configuration.nix`
4. Search for filename references - `grep -r "basename" --include="*.nix"`

**Key finding**: Many modules appear orphaned but are actually imported via `common-host.nix` or referenced by specific hosts (sentry, forge, nexus).

### Tooling Order
Run tools in this order for clean results:
```bash
# 1. Remove unused code
nix-shell -p deadnix --run 'deadnix /etc/nixos --edit'

# 2. Format (may need 2nd pass after deadnix)
nix-shell -p alejandra --run 'alejandra /etc/nixos'

# 3. Apply linter fixes
nix-shell -p statix --run 'statix fix /etc/nixos'

# 4. Final format pass
nix-shell -p alejandra --run 'alejandra /etc/nixos'
```

### Nix Overlay Pattern
```nix
# overlay.nix - Applies to ALL hosts via flake.nix
_: prev: {
  # Add new packages from local definitions
  myPackage = prev.callPackage ./packages/myPackage.nix {};

  # Override existing packages with custom build flags
  wivrn = prev.wivrn.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ ["-DFEATURE=ON"];
  });

  # Create backwards-compatible alias
  lm-studio = prev.lmstudio;
}
```

Applied via `flake.nix`:
```nix
commonModules = [
  {nixpkgs.overlays = [self.overlays.default];}
];
overlays.default = import ./overlay.nix;
```

### Bash String Interpolation Gotcha

**Wrong** - Creates invalid bash when condition is false:
```nix
SLACK_WEBHOOK="$$$(cat ${lib.optionalString (cfg.file != null) cfg.file} 2>/dev/null || echo '')"
# When false: SLACK_WEBHOOK="$(cat  2>/dev/null || echo '')"  ← BROKEN
```

**Correct** - Uses `/dev/null` fallback:
```nix
SLACK_WEBHOOK="$$$(cat ${if cfg.file != null then cfg.file else "/dev/null"} 2>/dev/null || echo '')"
# When false: SLACK_WEBHOOK="$(cat /dev/null 2>/dev/null || echo '')"  ← OK
```

### Environment Arrays with Optionals

```nix
Environment = [
  "PORT=${toString cfg.port}"
  "HOSTNAME=${config.networking.hostName}"
] ++ lib.optionals (cfg.slackWebhookUrlFile != null) [
  "SLACK_WEBHOOK=$(cat ${cfg.slackWebhookUrlFile})"
] ++ lib.optionals (cfg.discordWebhookUrlFile != null) [
  "DISCORD_WEBHOOK=$(cat ${cfg.discordWebhookUrlFile})"
] ++ lib.optionals cfg.email.enable [
  "EMAIL_ENABLED=true"
  "EMAIL_SMTP_HOST=${cfg.email.smtpHost}"
  "EMAIL_SMTP_PORT=${toString cfg.email.smtpPort}"
  "EMAIL_FROM=${cfg.email.from}"
  "EMAIL_TO=${cfg.email.to}"
  "EMAIL_USERNAME=${cfg.email.username}"
] ++ lib.optionals (cfg.email.enable && cfg.email.passwordFile != null) [
  "EMAIL_PASSWORD=$(cat ${cfg.email.passwordFile})"
];
```

### Tool Notes

**Alejandra** (Nix formatter)
- Uses 16 threads by default
- Exit code 1 = files need formatting
- May require multiple passes after other tools modify files

**Deadnix** (Unused code detection)
- Removes unused lambda pattern parameters
- `config, lib, pkgs, ...` → removes unused parameters
- Use `_: prev:` instead of `prev: @ {...}` when `self` unused

**Statix** (Nix linter)
- Finds code smells, duplication, deprecated patterns
- `statix fix` applies automatic corrections
- Some warnings require manual review

## MCP Server Integration (2026-03-05)

### Local vs Remote MCP Servers

**Local (stdio subprocess)**:
```nix
mcp.servers.nix-rebuild = {
  type = "local";
  command = [
    "${pkgs.python3.withPackages (ps: [ ps.mcp ]).interpreter}"
    "/etc/nixos/skills/nix-rebuild-mcp/server.py"
  ];
  environment = { NIX_HOST = "zephyr"; };
};
```

**Remote (HTTP/SSE)**:
```nix
mcp.servers.web-search-prime = {
  type = "remote";
  url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
  headers = { Authorization = "Bearer /run/agenix/zai-api-key"; };
};
```

### Gateway Integration

The AI Gateway (`modules/services/ai-inference/`) aggregates MCP servers and provides:
- Unified HTTP API for all tools
- Tool discovery via `/mcp/tools`
- Tool execution via `/mcp/call`
- Health monitoring for each server

## Plasma 6 on NixOS

### KSycoca Cache Issue

KDE's system configuration cache (`KSycoca`) stores Nix store paths that become invalid after rebuild, causing crashes.

**Symptoms**: Plasma components crash after `nixos-rebuild switch`

**Root Cause**: Cache contains old store paths like `/nix/store/abc...-kitemviews`

**Workaround**: Plasma auto-restarts after crash (acceptable for now)

**Failed Solutions**:
- `kde-cache-rebuild` service - used Qt5 instead of Qt6 (removed)
- Setting `KDESYCOCA` env var - broke Plasma service

**Status**: Architectural mismatch between Nix's immutable store and KDE's caching. No clean fix exists without upstream changes.

## AI Inference Gateway Architecture

### Backend Fallback Chain
```
Request → vllm (primary) → lm-studio (fallback) → zai (cloud)
         ↓               ↓                    ↓
    256K context    128K context         200K context
```

### MCP Broker Pattern
```python
# Aggregates tools from multiple MCP servers
async def get_all_tools():
    tools = []
    for server in mcp_servers.values():
        if server.enabled:
            tools.extend(await server.fetch_tools())
    return tools
```

### RAG Integration
- Vector search via Qdrant (sentence-transformers)
- BM25 keyword search as fallback
- Hybrid scoring: `0.7 * vector + 0.3 * bm25`
- Auto-RAG: triggers on confidence < 0.3

## Testing Procedures

### Before Any Nix Change
```bash
# 1. Fast syntax check (~5 seconds)
nix flake check

# 2. Build without applying (~2 minutes)
sudo nixos-rebuild build --flake .#zephyr

# 3. Test temporarily (rolls back on reboot)
sudo nixos-rebuild test --flake .#zephyr

# 4. Verify services
systemctl status ai-inference-gateway
curl http://127.0.0.1:8080/health

# 5. Apply persistently
sudo nixos-rebuild switch --flake .#zephyr
```

### Gateway Testing
```bash
# Health check
curl http://127.0.0.1:8080/health | jq .

# List models
curl http://127.0.0.1:8080/v1/models | jq .

# Test completion
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/qwen3.5-9b","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'

# List MCP tools
curl http://127.0.0.1:8080/mcp/tools | jq .

# Call MCP tool
curl -X POST http://127.0.0.1:8080/mcp/call \
  -H "Content-Type: application/json" \
  -d '{"server":"web-search-prime","tool":"webSearchPrime","arguments":{"search_query":"NixOS"}}'
```

## Common Patterns

### Service Module Template
```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.my-service;
  inherit (lib) mkEnableOption mkOption types mkIf;
in
{
  options.services.my-service = {
    enable = mkEnableOption "My Service";
    setting = mkOption { type = types.str; default = "value"; };
  };

  config = mkIf cfg.enable {
    # systemd service, packages, etc.
  };
}
```

### Conditional Imports
```nix
imports = [
  ./base.nix
] ++ lib.optional (hostName == "zephyr") ./zephyr-only.nix
  ++ lib.optionals (cfg.enableExtra) [ ./extra1.nix ./extra2.nix ];
```

### Prometheus scrape config
```nix
services.prometheus.scrapeConfigs = [
  {
    job_name = "my-service";
    static_configs = [{
      targets = ["127.0.0.1:${toString cfg.port}"];
      labels = { instance = config.networking.hostName; };
    }];
  }
];
```
