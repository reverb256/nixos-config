# Hermes Agent & AI Stack Improvement Plan

**Date:** 2026-03-16
**Status:** Design
**Priority:** Address critical deployment gaps before enabling Hermes

---

## Critical Fixes (Phase 0)

### Fix 1: Update Skills Commands (HIGH)

**Problem:** Skills reference `just test` which doesn't exist

**Files to update:**
- `modules/services/hermes-agent/skills/nixos-deployment/SKILL.md`
- `modules/services/hermes-agent/skills/cluster-management/SKILL.md`

**Changes:**
```markdown
### Test Configuration
```bash
nix flake check        # Validate flake
just build              # Build local configuration
```

### Deploy to All Hosts
```bash
just deploy            # Deploy to all hosts via Colmena
```
```

### Fix 2: Add Deployment Verification (HIGH)

**Problem:** No verification that Hermes actually works

**Add:** `modules/services/hermes-agent/health-check.nix`

```nix
{ config, lib, pkgs, ... }:
{
  systemd.services.hermes-health-check = {
    description = "Verify Hermes Agent is functional";
    script = ''
      # Check Hermes CLI responds
      ${pkgs.hermes-agent}/bin/hermes --version || exit 1

      # Check AI Gateway is reachable from Hermes
      ${pkgs.curl}/bin/curl -s ${config.services.ai-inference.backend.url}/health || exit 1

      # Check shared storage is mounted
      mountpoint -q /home/j_kro/.hermes || exit 1

      echo "✓ Hermes Agent health check passed"
    '';
    startAt = "multi-user.target";
    serviceConfig = {
      Type = "oneshot";
      User = "j_kro";
    };
  };

  # Run health check after Hermes user session starts
  systemd.timers.hermes-health-check = {
    wantedBy = [ "multi-user.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
    };
  };
}
```

### Fix 3: Fix Submodule Handling (MEDIUM)

**Problem:** Submodules fail silently with `|| true`

**Current:**
```nix
postUnpack = ''
  chmod -R u+w source
  cd source
  git submodule update --init --recursive || true  # ❌ Silent failure
 '';
```

**Improved:**
```nix
postUnpack = ''
  chmod -R u+w source
  cd source
  if ! git submodule update --init --recursive 2>&1; then
    echo "⚠️  Submodules failed to initialize, continuing anyway" >&2
    echo "    Some features (mini-swe-agent, tinker-atropos) may not work" >&2
  fi
  echo "✓ Submodule init completed" >&2
  echo "✓ Submodule init completed" >&2
'';
```

---

## Deep Integration Improvements (Phase 1)

### Integration 1: Hermes → MCP Broker (NEW)

**Problem:** Hermes cannot use the 12+ MCP tools already available

**Solution:** Add MCP client capability to Hermes

**Implementation:** `modules/services/hermes-agent/mcp-integration.nix`

```python
# Wrapper script that adds MCP tools to Hermes environment
# ~/.config/hermes/mcp-tools.yaml
mcpServers:
  web-search-prime:
    url: http://127.0.0.1:9000/mcp/web_search_prime
  searxng:
    url: http://127.0.0.1:9000/mcp/searxng
  context7:
    url: http://127.0.0.1:9000/mcp/context7
```

**Benefits:**
- Hermes gets web search, documentation lookup, code search
- No duplicate tool implementations
- Single source of truth for tool schemas

### Integration 2: AI Gateway → Hermes Memory (NEW)

**Problem:** No shared context between AI Gateway requests and Hermes

**Solution:** Make Hermes memory available to AI Gateway via Qdrant

**Implementation:**

```python
# ai_inference_gateway/memory/hermes_client.py
class HermesMemoryClient:
    """Query Hermes shared memory via NFS"""

    HERMES_MEMORY_PATH = "/var/lib/hermes/memory"  # Or NFS mount

    def get_context(self, query: str) -> List[str]:
        """Search Hermes memory for relevant context"""
        # Read from shared NFS storage
        # Returns relevant memories as context
        pass
```

### Integration 3: Unified Monitoring (NEW)

**Problem:** No observability into Hermes operations

**Solution:** Add Prometheus metrics

**Implementation:** `modules/services/hermes-agent/monitor.nix`

```nix
{ config, lib, pkgs, ... }:
{
  # Expose Hermes metrics to Prometheus
  services.prometheus.exporters.heroku = {
    enable = true;
    port = 9091;
  };

  # Or create custom exporter for Hermes
  systemd.services.hermes-metrics = {
    script = ''
      # Expose metrics for:
      # - hermes_commands_total
      # - hermes_commands_duration_seconds
      # - hermes_ai_gateway_calls_total
      # - herms_active_skills
      pass
    '';
  };
}
```

---

## Architectural Improvements (Phase 2)

### Architecture 1: Skill Generation Automation

**Problem:** Skills are hand-written static markdown

**Solution:** Auto-generate from existing docs

**Implementation:** `scripts/generate-hermes-skills.sh`

```bash
#!/usr/bin/env nix-shell
# Generate Hermes skills from cluster documentation

# Sources:
# - justfile → nixos-deployment skill
# - ROADMAP.md → k8s-migration skill
# - AGENTS.md → cluster-management skill
# - modules/services/ai-inference/* → ai-gateway-config skill

OUTPUT_DIR="modules/services/hermes-agent/skills"

# Generate each skill with metadata
# This ensures skills stay in sync with actual docs
```

### Architecture 2: Python Version Alignment

**Problem:** Hermes (3.11) vs AI Gateway (system Python)

**Options:**

1. **Package Hermes with Python 3.13** (preferred)
   - Test Hermes with 3.13
   - If compatible, update `package.nix`

2. **Run Hermes in isolated environment**
   - Use `nix-shell` with specific Python
   - Wrapper script handles environment

3. **Run Hermes as container**
   - Podman container with Python 3.11
   - Easier updates and isolation

### Architecture 3: Containerization for K8s

**Problem:** Not ready for Kubernetes migration

**Solution:** Create Podman container definition

**Implementation:** `containers/hermes-agent-container.nix`

```nix
{ pkgs, ... }:
{
  hermes-agent-container = pkgs.podman.buildImage {
    name = "hermes-agent";
    config = {
      Cmd = [ "hermes" ];
      Env = [
        "HERMES_AI_GATEWAY_URL=http://ai-gateway:8080/v1"
        "OPENAI_API_KEY=not-needed"
      ];
    };
  };
}
```

---

## Implementation Priority

| Phase | Task | Effort | Impact | Dependencies |
|-------|------|--------|--------|--------------|
| **0** | Fix skills `just test` | Low | High | None |
| **0** | Add health check service | Medium | High | None |
| **0** | Fix submodule handling | Low | Medium | None |
| **0** | Verify deployment works | Medium | High | None |
| **1** | MCP integration | High | Very High | Hermes CLI changes |
| **1** | Unified monitoring | Medium | Medium | Prometheus |
| **2** | Skill automation | Medium | High | Documentation parsing |
| **2** | Container definition | Low | Medium | Podman |

---

## Success Criteria

After improvements:

- [ ] All skills use correct commands (`just check`, `just build`)
- [ ] Health check confirms Hermes works on all nodes
- [ ] Submodule initialization is logged (not silent)
- [ ] Hermes can call MCP broker tools
- [ ] Hermes memory is queryable by AI Gateway
- [ ] Metrics exposed to Prometheus
- [ ] Skills auto-generated from docs
- [ ] Container definition exists for K8s migration

---

## Next Steps

1. **Immediate:** Fix skills `just test` → `just check`/`just build`
2. **Today:** Verify Hermes actually works on at least one node
3. **This week:** Add health check service
4. **Soon:** MCP integration design and implementation

---

## References

- Hermes Docs: https://hermes-agent.nousresearch.com/
- MCP Protocol: https://modelcontextprotocol.io/
- Current Plan: `docs/plans/2026-03-16-hermes-agent-implementation.md`
