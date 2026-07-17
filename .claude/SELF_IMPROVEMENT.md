# Self-Improvement System for NixOS Cluster

Your cluster now has a complete meta-learning ecosystem that learns from every interaction.

## Quick Reference

| Trigger | Action |
|---------|--------|
| Any tool use | Logged to working memory |
| Bash error | Captured for self-correction |
| Session ends | Pattern extraction triggered |
| `/learn <topic>` | Research and generate new skill |
| "自我进化" | Manual self-improvement trigger |

## Memory Structure

```
/home/j_kro/.claude/projects/-etc-nixos/memory/
├── semantic-patterns.json    # Reusable patterns with confidence scores
├── episodic/                 # Specific experiences (YYYY-MM-DD-{skill}.json)
├── working/                  # Current session state
├── references/               # Documentation
└── README.md
```

## Installed Skills

| Skill | Purpose |
|-------|---------|
| `self-improving-agent` | Meta-learning from all experiences |
| `subagent-driven-development` | Parallel execution with fresh agents |
| `deep-agents-memory` | Persistent storage backends |
| `memory-merger` | Consolidate mature lessons |
| `self-learning` | `/learn` new technologies |

## Using the System

### Manual Self-Improvement

Say any of these to trigger pattern extraction:
- "自我进化"
- "self-improve"
- "从经验中学习"
- "分析今天的经验"

### Learning New Topics

```
/learn kubernetes-gpu-scheduling
/learn metallb-bare-metal
/learn cilium-network-policies
```

### Memory Merge

```
memory-merge nixos global
memory-merge kubernetes workspace
```

Or use the skill: `/memory-merger >nixos`

## Hooks Automation

The system automatically tracks:
1. **PreToolUse**: Captures context before destructive operations
2. **PostToolUse**: Captures Bash errors for self-correction
3. **Stop**: Triggers session-end pattern extraction

## NixOS-Specific Patterns

Critical patterns already encoded:
- `nixos-mkoptiondefault-001`: Use `lib.mkOptionDefault` for extensible options
- `nixos-rebuild-foreground-001`: Never background `nixos-rebuild`
- `nixos-testing-checklist-001`: Test on specific nodes per file changed

View all: `~/.agents/skills/self-improving-agent/references/nixos-patterns.md`

## Pattern Confidence

Patterns are scored 0-1 and evolve based on:
- Successful applications (increases confidence)
- User feedback (rating 1-10)
- Time since last use (decay)

## Episodic Memory Template

```json
{
  "id": "ep-YYYY-MM-DD-001",
  "skill": "skill-name",
  "outcome": "success|partial|failure",
  "lesson": "Key takeaway",
  "related_pattern": "pattern-id"
}
```

## Next Steps

1. **Work normally** - the system learns automatically
2. **Provide feedback** - rate outcomes 1-10 when asked
3. **Review patterns** - check `semantic-patterns.json` periodically
4. **Use /learn** - expand knowledge base for new topics

## Files Modified During Setup

- `~/.claude/settings.json` - Added hooks configuration
- `~/.agents/skills/self-improving-agent/hooks/*` - Automation scripts
- `/etc/nixos/memory/*` - Memory structure and documentation
