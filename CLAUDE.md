# NixOS Configuration - Claude Code Agent Patterns

## Purpose
This document contains Claude Code-specific patterns and workflows for this NixOS configuration. It extends the universal guidelines in `AGENTS.md` with Claude Code features like Serena semantic tools and async agent launching.

**Read AGENTS.md first** for universal cluster patterns, build commands, and deployment workflows.

---

## Quick Start

1. Read `AGENTS.md` for universal cluster patterns
2. Use Serena semantic tools for code understanding
3. Launch async agents for parallel independent tasks
4. Always use `just` commands for CI/CD integration


---



---


## Claude Code-Specific Features

### Serena Semantic Tools
Powerful code understanding for navigating NixOS configurations:

**find_symbol**: Locate symbols by name
```
find_symbol(name_path_pattern="ClusterStorage", relative_path="...")
```

**find_referencing_symbols**: Find all references
```
find_referencing_symbols(name_path="ensureStorageMounted", ...)
```

**get_symbols_overview**: Quick file structure
```
get_symbols_overview(relative_path="hosts/zephyr/...", depth=1)
```

### Async Agent Launching
Launch multiple agents for parallel independent tasks:
```python
Agent(description="Analyze storage", prompt="...")
Agent(description="Review GPU setup", prompt="...")
```

### Claude MCP Integration
Always include Accept header for ZAI MCP:
```bash
curl -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $(cat /run/agenix/zai-api-key)" \
  https://api.z.ai/api/mcp/web_search_prime/mcp
```

See: `.claude/hookify.warn-mcp-accept-headers.local.md`

---



---


---


---



## See Also

### Universal Documentation
- **AGENTS.md**: Universal patterns for all agents
  - Build & test commands (just commands)
  - Deployment workflows (Colmena, multi-host)
  - Kubernetes migration (9-week plan)
  - MCP integration (protocol, troubleshooting)

- **DOCUMENTATION_INDEX.md**: Comprehensive documentation index
- **ROADMAP.md**: Complete Kubernetes migration plan

### Cluster Information
- **Hosts**: Zephyr (control plane), Nexus (storage), Forge (GPU), Sentry (monitoring)
- **Resources**: 78 cores, 123GB RAM, 7 GPUs (5x NVIDIA + 2x AMD), 8.4TB storage
- **Architecture**: NixOS flakes, profile-based, declarative configuration

### Workflow Commands
```bash
just test              # Verify configuration
just switch            # Apply to local host
just deploy            # Deploy to all hosts
just sync              # Sync all nodes to current branch
```

---

**Version**: 1.0 | **Updated**: 2026-03-08
**Generated from**: `/etc/nixos/docs/templates/base-template.md.j2`

