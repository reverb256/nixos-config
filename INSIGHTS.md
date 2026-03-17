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

## Grafana Admin Password Recovery (2026-03-06)

### When Login Fails

**Symptom**: "Invalid username or password" even after reset
**Cause**: Grafana temporarily locks accounts after too many failed attempts

**Recovery Procedure**:
```bash
# 1. Clear login attempts from database
sudo sqlite3 /var/lib/grafana/data/grafana.db "DELETE FROM login_attempt WHERE username = 'admin';"

# 2. Reset password using Grafana CLI
sudo -u grafana /nix/store/*-grafana-*/bin/grafana cli \
  --homepath /var/lib/grafana \
  admin reset-admin-password NewPassword123

# 3. Restart Grafana
sudo systemctl restart grafana

# 4. Test login
curl -s -X POST http://127.0.0.1:3001/login \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","password":"NewPassword123"}'
```

### Agenix Secret Management

```bash
# Create new secret
echo "password" | nix run github:ryantm/agenix -- -e secrets/secret-name.age

# Edit existing secret
nix run github:ryantm/agenix -- -e secrets/secret-name.age

# Re-encrypt for new hosts
# Update secrets.nix with new host keys, then:
nix run github:ryantm/agenix -- -r
```

### Grafana Configuration with Agenix

```nix
# In grafana.nix
age.secrets.grafana-admin = {
  file = ./secrets/grafana-admin.age;
  owner = "grafana";
  group = "grafana";
  mode = "0400";
};

services.grafana.settings.security.admin_password = "$__file{/run/agenix/grafana-admin}";
```

## Monitoring Cluster Status (2026-03-06)

### Cluster Nodes

| Host | Node Exporter (9100) | Mining Exporter (9105) | NVIDIA GPU (9400) | Status |
|------|---------------------|----------------------|-------------------|--------|
| **zephyr** | ✅ UP | ✅ UP | ✅ UP | Healthy |
| **sentry** | ✅ UP | ❌ DOWN | N/A (AMD) | Mining exporter needs fix |
| **forge** | ✅ UP | ✅ UP | ✅ UP | Healthy |
| **nexus** | ❌ DOWN | ❌ DOWN | ❌ DOWN | Host offline |

### Services

- **Prometheus** (zephyr:9090): Running, scraping all targets
- **Grafana** (zephyr:3001): Running, credentials secured via agenix
- **Node Exporter**: Running on zephyr, sentry, forge
- **Mining Exporter**: Running on zephyr, forge; needs fix on sentry
- **NVIDIA Exporter**: Running on zephyr, forge

### Known Issues

1. **Sentry Mining Exporter**: Service not running on port 9105
   - Host is reachable (ping, node-exporter work)
   - Mining exporter enabled in config but service not starting
   - Requires investigation on sentry host

2. **Nexus Host**: All exporters timing out
   - Host appears to be offline (Tailscale timeout)
   - Needs to be brought back online

3. **Grafana Access**: Tailscale interface only
   - Local access: http://127.0.0.1:3001
   - Via Tailscale: https://grafana.ts.krogh.dev/
   - Credentials stored in agenix: `secrets/grafana-admin.age`

## Home Manager Module Validation (2026-03-16)

### Always Validate Options Before Committing

**Problem**: Assuming options exist without validation leads to broken configurations.

**Case Study**: `xdg.mimeApps.force` option
- Commit `84f0518` attempted to fix idempotent activation with `force = true`
- Commit `4321891` perpetuated this "fix"
- **Problem**: The option doesn't exist in Home Manager's `xdg.mimeApps` module
- **Impact**: `nix flake check` fails with "option does not exist" error

### Home Manager xdg.mimeApps Valid Options

```nix
# VALID options in Home Manager's xdg.mimeApps module:
xdg.mimeApps.enable = true;              # Boolean
xdg.mimeApps.associations = { ... };     # Custom MIME associations
xdg.mimeApps.defaultApplications = {     # Default app mappings
  "text/html" = "zen-twilight.desktop";
  "x-scheme-handler/https" = "zen-twilight.desktop";
};

# INVALID - does NOT exist:
xdg.mimeApps.force = true;  # ❌ This option is not real
```

### Option Validation Workflow

```bash
# Before committing ANY option, validate it exists:
nix flake check . 2>&1 | grep -i "option.*does not exist"

# For Home Manager specific options, check docs:
nix build -f '<home-manager>' docs  # If available

# Or evaluate the option directly:
nix eval .#nixosConfigurations.zephyr.config.home-manager.users.j_kro.xdg.mimeApps
```

### Multi-File Commit Risks

**Problem**: Scoped commits (e.g., "refactor(mining)") can accidentally touch unrelated files.

**Example**: Commit `e6452c9` was titled "refactor(mining): remove deprecated Python gpu-proxy module" but also modified `modules/home-manager/zen-browser.nix`.

**Mitigation**:
```bash
# After making changes, verify the scope:
git diff --cached --name-only

# If unrelated files appear, unstage them:
git restore --staged <unrelated-file>
```

### Git Staging Confusion

**Problem**: Staged changes can silently override HEAD, causing confusion about what's actually committed.

**Scenario**:
1. Edit file, stage it (`git add`)
2. Later, `git checkout HEAD -- file` restores to HEAD
3. Working directory now differs from staged version
4. Commit uses staged version, not working directory

**Mitigation**: Always check `git status` before committing:
```bash
# Shows what will be committed (staged):
git status

# Compare staged vs working directory:
git diff --cached <file>
git diff <file>
```

### Idempotent Activation Without `force`

Since `xdg.mimeApps.force` doesn't exist, handle activation differently:

```nix
# Approach 1: Use xdg.configFile for manual control
xdg.configFile."mimeapps.list".force = true;  # This DOES exist

# Approach 2: Accept that Home Manager may create .bak files
# The backup files are harmless and indicate idempotent runs
```

## Testing Before Deployment (2026-03-16)

### Pre-Commit Checklist

```bash
# 1. Syntax validation (fast, ~5 seconds)
nix flake check .

# 2. Check for non-existent options
nix flake check . 2>&1 | grep "does not exist"

# 3. Verify staged changes match intent
git status
git diff --cached --stat

# 4. Only then commit
git commit -m "feat(description): details"
```

### Understanding Flake Check Warnings

```
warning: 'system' has been renamed to/replaced by 'stdenv.hostPlatform.system'
```
- **Impact**: Usually benign, indicates using deprecated variable names
- **Action**: Update `system` → `stdenv.hostPlatform.system` when convenient

```
warning: unknown flake output 'colmenaHive'
```
- **Impact**: Benign, output exists but `nix flake check` doesn't recognize the schema
- **Action**: Can be ignored
