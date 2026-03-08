# NixOS Configuration - Qwen-Agent Patterns

## Purpose
This document contains Qwen-Agent-specific patterns and workflows for this NixOS configuration. It extends the universal guidelines in `AGENTS.md` with Qwen framework features like function calling, code interpreter, and Qwen MCP integration.

**Read AGENTS.md first** for universal cluster patterns, build commands, and deployment workflows.

---

## Quick Start

1. Read `AGENTS.md` for universal cluster patterns
2. Use Qwen framework patterns for agent workflows
3. Configure MCP with Qwen-specific settings
4. Follow universal deployment workflows


---



---



## Qwen-Agent-Specific Features

### Qwen Framework
```bash
pip install -U 'qwen-agent[mcp,rag,code_interpreter]'
```

### Tool Usage
```python
from qwen_agent import Agent

agent = Agent(
    llm={'model': 'qwen-turbo'},
    function_list=[search_db, run_cmd]
)
```

### MCP Integration
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/etc/nixos"]
    }
  }
}
```

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

