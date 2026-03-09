# NixOS Configuration - Claude Code Agent Patterns

## Purpose
This document contains Claude Code-specific patterns and workflows for this NixOS configuration. It extends the universal guidelines in `AGENTS.md` with Claude Code features like Serena semantic tools and async agent launching.

**Read AGENTS.md first** for universal cluster patterns, build commands, and deployment workflows.

---

## Quick Start

1. Read `AGENTS.md` for universal cluster patterns
2. **Use Serena semantic tools for ALL code understanding** (see section below)
3. Launch async agents for parallel independent tasks
4. Always use `just` commands for CI/CD integration


---



---

## When to Use Serena Semantic Tools

**Use Serena for ALL complex code understanding tasks:**

### ✅ Use Serena When:
- **Understanding module structure** - `get_symbols_overview()` for file architecture
- **Finding symbol definitions** - `find_symbol()` to locate functions, classes, options
- **Tracing references** - `find_referencing_symbols()` to see where symbols are used
- **Multi-step refactoring** - Symbol-aware edits preserve structure
- **Cross-file analysis** - Understanding relationships between modules
- **Large codebase navigation** - Quickly locate patterns without reading entire files

### ❌ Use Standard Tools When:
- **Simple file reading** - `Read` for single files you already know
- **Basic pattern matching** - `Grep` for simple text searches
- **File discovery** - `Glob` for finding files by pattern
- **Quick fixes** - `Edit` for simple, localized changes

### Key Principle:
**Serena is DEFAULT for code understanding.** Only use Read/Grep/Glob when you have a clear, simple target. Serena's semantic understanding prevents errors in complex NixOS module structures.

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
# just sync              # Sync all nodes to current branch (DEPRECATED: Colmena handles this automatically)
```

---

**Version**: 1.1 | **Updated**: 2026-03-09
**Generated from**: `/etc/nixos/docs/templates/base-template.md.j2`

