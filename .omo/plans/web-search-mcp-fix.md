# Web Search MCP Comprehensive Fix Plan

**Created**: 2026-03-25
**Status**: Draft
**Priority**: High

## Problem Statement

The Claude Code "web search" MCP functionality is broken due to:
1. Original wrapper requires `ai-inference-gateway` package which isn't installed
2. Local SearXNG service (port 7777) not running
3. MCP gateway bridge can't connect to gateway service
4. Configuration fragmentation across multiple locations

## Current State Analysis

### Working Components
| Component | Status | Details |
|-----------|--------|---------|
| External SearXNG | ✅ Working | `https://search.reverb256.ca` responds with JSON API |
| mcp-searxng PyPI | ✅ Working | Version 0.1.0 via `uvx --from mcp-searxng mcp-searxng` |
| Other MCP servers | ✅ Working | filesystem, git, fetch, context7, playwright |
| New wrapper script | ✅ Created | `/etc/nixos/modules/services/ai-inference/bin/searxng-mcp-wrapper` |

### Broken Components
| Component | Issue | Action |
|-----------|-------|--------|
| `opencode-searxng-mcp` | Requires ai-inference-gateway package | Remove/Archive |
| Local SearXNG (7777) | No systemd service or Docker container | Defer |
| mcp-gateway-bridge | Gateway not running at `http://ai.cluster.local` | Remove from config |
| Brave Search MCP | Missing `BRAVE_API_KEY` | Defer |

### Configuration Locations
1. `/etc/nixos/.mcp.json` - Main MCP config (updated)
2. `/etc/nixos/skills/searxng-mcp/server.py` - Standalone server (broken)
3. `/etc/nixos/scripts/searxng-default-search.sh` - Integration test script
4. `/etc/nixos/scripts/test-search.sh` - Search wrapper tests
5. `/etc/nixos/modules/services/ai-inference/bin/opencode-searxng-mcp` - Old wrapper

---

## Implementation Plan

### Phase 1: Quick Fix (Immediate - Get Working)

**Goal**: Enable web search using external SearXNG instance

#### Task 1.1: Verify External SearXNG
```bash
# Test JSON API response
curl -s "https://search.reverb256.ca/search?q=nixos&format=json" | jq '.results | length'
# Expected: > 0
```

#### Task 1.2: Verify New Wrapper
```bash
# Test wrapper with MCP handshake
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}' | \
SEARXNG_URL="https://search.reverb256.ca" timeout 10 /etc/nixos/modules/services/ai-inference/bin/searxng-mcp-wrapper
# Expected: Valid JSON-RPC response with serverInfo
```

#### Task 1.3: Update .mcp.json
- [x] Change `searxng.command` to use new wrapper
- [x] Keep `SEARXNG_URL` pointing to external instance
- [ ] Remove `gateway` server entry (not working)
- [ ] Verify file is not immutable

#### Task 1.4: Remove Broken Components
```bash
# Archive old wrapper
mv /etc/nixos/modules/services/ai-inference/bin/opencode-searxng-mcp \
   /etc/nixos/modules/services/ai-inference/bin/opencode-searxng-mcp.broken

# Archive standalone server (requires mcp package not in PATH)
mv /etc/nixos/skills/searxng-mcp /etc/nixos/skills/searxng-mcp.archived
```

#### Task 1.5: Update Test Scripts
- Update `scripts/searxng-default-search.sh` to test only working components
- Create simple test script that verifies external SearXNG + wrapper

#### Task 1.6: Verification
```bash
# Full integration test
(echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}}}'; \
 sleep 0.5; \
 echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search","arguments":{"query":"nixos flakes"}}}') | \
SEARXNG_URL="https://search.reverb256.ca" timeout 30 /etc/nixos/modules/services/ai-inference/bin/searxng-mcp-wrapper
# Expected: JSON response with search results
```

---

### Phase 2: Cleanup & Documentation (After Phase 1)

#### Task 2.1: Clean Configuration
- Remove `gateway` entry from `.mcp.json`
- Remove `mcp-gateway-bridge` references
- Consolidate all SearXNG configuration in one place

#### Task 2.2: Create Documentation
- Document current architecture in `docs/web-search-mcp.md`
- Update AGENTS.md with web search usage notes
- Create troubleshooting guide

#### Task 2.3: Create Monitoring
- Add health check script for external SearXNG
- Add to systemd timer for periodic checks
- Log failures to cluster monitoring

---

### Phase 3: Future Enhancements (Deferred)

#### Option A: Local SearXNG Deployment
```nix
# modules/services/searxng.nix
services.searxng = {
  enable = true;
  settings = {
    server.port = 7777;
    search.formats = [ "json" "html" ];
  };
};
```

#### Option B: Brave Search Alternative
```json
{
  "brave-search": {
    "command": "mcp-brave-search",
    "env": {
      "BRAVE_API_KEY": "${BRAVE_API_KEY}"
    }
  }
}
```

#### Option C: AI Inference Gateway Integration
- Deploy gateway service to cluster
- Enable MCP broker functionality
- Consolidate all MCP servers through gateway

---

## Testing Checklist

### Phase 1 Tests
- [ ] External SearXNG responds to JSON API queries
- [ ] Wrapper script executes without errors
- [ ] `.mcp.json` correctly references new wrapper
- [ ] Claude Code can invoke web search tool
- [ ] Search results are returned correctly

### Phase 2 Tests
- [ ] All broken components archived/removed
- [ ] Documentation updated
- [ ] Health check script working
- [ ] Monitoring alerts configured

---

## Rollback Plan

If Phase 1 fails:
1. Restore original `.mcp.json` from backup
2. Unarchive `opencode-searxng-mcp` if needed
3. Document what failed for future attempts

---

## Success Criteria

1. **Immediate**: Claude Code web search MCP returns results
2. **Short-term**: Clean configuration, no broken components
3. **Long-term**: Resilient multi-source web search (external + local + brave)

---

## File Changes Summary

| File | Action | Priority |
|------|--------|----------|
| `/etc/nixos/.mcp.json` | Update, remove gateway | High |
| `bin/opencode-searxng-mcp` | Archive | High |
| `bin/searxng-mcp-wrapper` | Keep (working) | High |
| `skills/searxng-mcp/` | Archive | Medium |
| `scripts/searxng-default-search.sh` | Update | Medium |
| `scripts/test-searxng-direct.sh` | Keep (new) | Low |

---

## Notes

- External SearXNG instance is reliable and privacy-respecting
- `uvx` pattern works well for Python-based MCP servers
- Consider adding fallback URL in wrapper for resilience
- Monitor PyPI `mcp-searxng` package for updates
