# AI Agent Documentation Patterns

## Multi-File Documentation Structure

Based on research of 2,500+ repositories and official Anthropic best practices.

### File Hierarchy

```
PROJECT ROOT
├── AGENTS.md                    # Universal patterns (ALL agents)
├── CLAUDE.md                    # Claude Code context
├── .github/copilot-instructions.md  # GitHub Copilot
├── .cursorrules                 # Cursor IDE
├── QWEN.md                      # Qwen-Agent
└── .claude/                     # Claude-specific
    ├── agents/                  # Sub-agents
    └── skills/                  # Specialized skills
```

### File Responsibilities

| File | Purpose | Line Target | Primary Audience |
|------|---------|-------------|------------------|
| AGENTS.md | Universal patterns, all agents | ~200 | All AI tools |
| CLAUDE.md | Claude-specific context | <200 | Claude Code |
| copilot-instructions.md | Copilot instructions | <150 | GitHub Copilot |
| .cursorrules | Cursor IDE rules | <150 | Cursor |
| QWEN.md | Qwen-Agent context | <200 | Qwen-Agent |

### WHY/WHAT/HOW Structure (Recommended for CLAUDE.md)

```markdown
# Project Name

## WHAT
1-2 line project description and tech stack

## COMMANDS
Essential commands only (dev, test, build)

## PROJECT STRUCTURE
Directory tree or overview

## CONVENTIONS
Only non-default patterns

## WORKFLOW
Standard development flow

## REFERENCE DOCUMENTS
Progressive disclosure via @imports
```

### Progressive Disclosure Pattern

**Root files** (always loaded):
- Essential commands
- Critical conventions
- Project structure

**Detailed docs** (loaded on-demand):
- Use `@path/to/doc.md` syntax
- Skills in `.claude/skills/`
- Rules in `.claude/rules/`

### Safety Constraints (Critical)

```nix
# ✅ CORRECT - MERGES with node configs
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 53 6443];

# ❌ WRONG - REPLACES node configs
networking.firewall.allowedTCPPorts = [22 53 6443];
```

### Cross-Reference Pattern

AGENTS.md → Links to agent-specific files
CLAUDE.md → References AGENTS.md for universal patterns
QWEN.md → References AGENTS.md for universal patterns
copilot-instructions.md → References CLAUDE.md as primary source

### Update Workflow

1. Make changes to documentation
2. Update version and date
3. Test with actual AI agent workflows
4. Gather feedback from team
5. Iterate based on usage patterns

---

**References:**
- [TurboDocx CLAUDE.md Best Practices](https://www.turbodocx.com/blog/how-to-write-claude-md-best-practices)
- [Juice Shop Multi-Agent Pattern](https://github.com/juice-shop/juice-shop/blob/master/AGENTS.md)
- [Anthropic CLAUDE.md Documentation](https://code.claude.com/docs/en/best-practices)
