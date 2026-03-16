# NixOS Cluster - Qwen-Agent Context

## WHAT
NixOS flake-based 4-host Linux cluster (Zephyr, Nexus, Forge, Sentry) for AI inference, GPU computing, storage, and monitoring.

**Tech stack**: NixOS flakes, Kubernetes, Colmena, Just, Qwen framework

---

## COMMANDS
```bash
just test              # Verify configuration builds
just switch            # Apply to local host (auto-pauses CPU mining)
just deploy            # Deploy to all hosts via Colmena
just ci-local          # Full CI pipeline locally
```

---

## PROJECT STRUCTURE
```
/etc/nixos/
├── flake.nix              # Main flake with host definitions
├── hosts/                 # Per-host configs (zephyr, nexus, forge, sentry)
├── modules/               # Reusable modules
│   ├── profiles/          # Hardware, role, network profiles
│   └── system/            # System-level modules
├── justfile               # CI/CD commands
├── AGENTS.md              # Universal patterns for ALL agents
├── QWEN.md                # This file
└── .github/copilot-instructions.md  # GitHub Copilot instructions
```

---

## CONVENTIONS
- **IMPORTANT**: Use `lib.mkOptionDefault` in shared modules (NEVER direct assignment)
  - Direct assignment breaks SSH on all nodes
  - See @AGENTS.md Critical Safety Constraints for examples
- 2-space indentation, trailing semicolons
- kebab-case for files and modules
- Line length 80-100 chars (soft limit 120)

---

## QWEN-SPECIFIC SETUP

### Framework Installation
```bash
pip install -U 'qwen-agent[mcp,rag,code_interpreter]'
```

### Agent Configuration
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

## WORKFLOW
1. Make changes
2. `git add` new files (Nix only packages git-tracked files!)
3. `git commit`
4. `just test` (verifies configuration)
5. `just deploy` (applies to all hosts via Colmena)

**Test before deployment:**
- `modules/networking/*` → Test SSH on zephyr AND nexus
- `modules/system/ssh.nix` → Test SSH on all 4 nodes
- `modules/system/users.nix` → Test login on all 4 nodes

**Stop immediately if:**
- SSH breaks on any node → Document incident, wait for human
- Multiple nodes affected → STOP ALL WORK

---

## REFERENCE DOCUMENTS

### AGENTS.md — `@AGENTS.md`
**Read when:** First time working on this cluster
Universal patterns for ALL AI agents (Claude, Cursor, Copilot, Qwen-Agent)

### CLAUDE.md — `@CLAUDE.md`
**Read when:** Using Claude Code on this cluster
Claude Code-specific patterns and Serena tools

### Kubernetes Roadmap — `@ROADMAP.md`
**Read when:** Working on Kubernetes migration
Complete 9-week migration plan

---

## RELATED RESOURCES
- **Cluster Health**: `just status` or read STATUS.md
- **Documentation Index**: `@DOCUMENTATION_INDEX.md` for full catalog
- **Hookify Rules**: `.claude/hookify-*.md` for deployment safety

---

**Version**: 2.0 | **Updated**: 2026-03-15
**Changes**: Reformatted to match CLAUDE.md structure, added progressive disclosure

