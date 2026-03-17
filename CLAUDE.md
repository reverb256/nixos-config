# NixOS Cluster - Claude Code Context

## WHAT
NixOS flake-based 4-host Linux cluster (Zephyr, Nexus, Forge, Sentry) for AI inference, GPU computing, storage, and monitoring.

**Tech stack**: NixOS flakes, Kubernetes, Colmena, Just, Serena tools

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
└── .claude/               # Claude-specific files (agents, skills, settings)
```

---

## CONVENTIONS
- **IMPORTANT**: Use `lib.mkOptionDefault` in shared modules (NEVER direct assignment)
  - Direct assignment breaks SSH on all nodes
  - See @AGENTS.md Critical Safety Constraints for examples
- **CRITICAL**: NEVER background nixos-rebuild or similar long-running commands
  - Commands like `nixos-rebuild test`, `nixos-build`, `colmena apply` MUST show real-time output
  - User needs to see build progress, errors, and ETA
  - Backgrounding hides output and causes confusion
  - Always let these commands run normally with visible output
- 2-space indentation, trailing semicolons
- kebab-case for files and modules
- Line length 80-100 chars (soft limit 120)

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

## SERENA TOOLS
**Use Serena for:**
- Understanding module structure (`get_symbols_overview()`)
- Finding symbol definitions (`find_symbol()`)
- Tracing references (`find_referencing_symbols()`)
- Multi-step refactoring or cross-file analysis

**Use standard tools for:**
- Simple file reading (`Read`)
- Basic pattern matching (`Grep`)
- File discovery (`Glob`)

---

## REFERENCE DOCUMENTS

### AGENTS.md — `@AGENTS.md`
**Read when:** First time working on this cluster
Universal patterns for ALL AI agents (Claude, Cursor, Copilot, Qwen-Agent)

### Multi-Host Validator — `.claude/agents/multi-host-validator.md`
**Read when:** Editing files in `modules/` directory
Validates multi-host impact using checklist

### Add-Service Skill — `.claude/skills/add-service/SKILL.md`
**Read when:** Adding new NixOS services
Step-by-step service addition workflow

### Nix-Rebuild Skill — `.claude/skills/nix-rebuild/SKILL.md`
**Read when:** Working with NixOS rebuild commands
Safe rebuild patterns and troubleshooting

### Kubernetes Roadmap — `@ROADMAP.md`
**Read when:** Working on Kubernetes migration
Complete 9-week migration plan

---

## RELATED RESOURCES
- **Cluster Health**: `just status` or read STATUS.md
- **Documentation Index**: `@DOCUMENTATION_INDEX.md` for full catalog
- **Hookify Rules**: `.claude/hookify-*.md` for deployment safety

---

**Version**: 4.0 | **Updated**: 2026-03-15
**Changes**: Reformatted per Anthropic best practices - WHY/WHAT/HOW structure, under 200 lines, progressive disclosure via @imports
