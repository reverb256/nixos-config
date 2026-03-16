# Documentation Upgrade - March 15, 2026

## Overview
Upgraded CLAUDE.md and AGENTS.md based on research of 2,500+ repositories and official Anthropic best practices.

## Key Changes

### 1. CLAUDE.md (v4.0)
**Structure**: WHY/WHAT/HOW pattern
- WHAT: Project overview in 1-2 lines
- COMMANDS: Essential commands only
- PROJECT STRUCTURE: Directory tree
- CONVENTIONS: Critical patterns (lib.mkOptionDefault)
- WORKFLOW: Standard development flow
- REFERENCE DOCUMENTS: Progressive disclosure via @imports

**Metrics**: 109 lines (under 200 target) ✅

### 2. AGENTS.md (v2.0)
**Focus**: Universal patterns for ALL AI agents
- Cross-tool compatibility (Claude, Cursor, Copilot, Qwen, etc.)
- Links to agent-specific instruction files
- Critical safety constraints emphasized
- Progressive disclosure pattern

**Metrics**: 201 lines (universal reference) ✅

### 3. New Agent-Specific Files

| File | Purpose | Lines | Audience |
|------|---------|-------|----------|
| `.github/copilot-instructions.md` | GitHub Copilot instructions | 100 | Copilot |
| `.cursorrules` | Cursor IDE rules | 99 | Cursor |
| `QWEN.md` (v2.0) | Qwen-Agent context | 120 | Qwen-Agent |

### 4. Documentation Standards

**Multi-File Pattern** (v2.0):
- Root files: Essential patterns (<200 lines)
- Detailed docs: Loaded via `@imports`
- Skills: Loaded on-demand based on triggers
- Hookify rules: Enforce safety constraints

## Files Changed

```
/etc/nixos/
├── AGENTS.md (v2.0)              # Universal patterns
├── CLAUDE.md (v4.0)              # Claude context
├── QWEN.md (v2.0)                # Qwen context
├── .github/copilot-instructions.md (NEW)
├── .cursorrules (NEW)
├── DOCUMENTATION_INDEX.md (v2.0) # Updated structure
└── docs/templates/AGENT-DOC-PATTERNS.md (NEW)
```

## Research Sources

- **TurboDocx**: CLAUDE.md structure and progressive disclosure
- **GitHub Repositories**: Juice Shop, Umbraco, Cypress, open-notebook
- **Anthropic**: Official CLAUDE.md guidelines
- **Linux Foundation**: AGENTS.md standard

## Testing Checklist

- [ ] Verify CLAUDE.md loads correctly in Claude Code
- [ ] Test AGENTS.md with Cursor/Copilot/Qwen-Agent
- [ ] Validate cross-references between files
- [ ] Check progressive disclosure via @imports
- [ ] Confirm safety constraints are enforced

## References

- [TurboDocx Best Practices](https://www.turbodocx.com/blog/how-to-write-claude-md-best-practices)
- [Juice Shop AGENTS.md](https://github.com/juice-shop/juice-shop/blob/master/AGENTS.md)
- [Anthropic Documentation](https://code.claude.com/docs/en/best-practices)
