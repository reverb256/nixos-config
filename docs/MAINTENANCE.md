# Agent Instruction Files Maintenance Guide

**Last Updated:** 2026-03-08
**Template System Version:** 1.0
**Generated Files:** AGENTS.md, CLAUDE.md, QWEN.md

---

## Overview

Agent instruction files are generated from Jinja2 templates to eliminate duplication and ensure consistency. This document describes the maintenance workflow for updating these files.

## File Structure

```
/etc/nixos/docs/
├── templates/
│   ├── base-template.md.j2              # Main Jinja2 template
│   └── shared/
│       ├── kubernetes-migration.md      # Shared Kubernetes content
│       ├── mcp-integration.md           # Shared MCP content
│       ├── build-test-commands.md       # Shared build/test content
│       └── deployment-workflows.md      # Shared deployment content
├── generate-agent-instructions.py       # Generation script
├── validate-agent-files.py              # Validation script
├── MAINTENANCE.md                        # This file
└── plans/
    └── 2026-03-08-agent-instruction-files-spec-design.md  # Design document

/etc/nixos/ (Generated outputs)
├── AGENTS.md                             # Universal patterns (327 lines)
├── CLAUDE.md                             # Claude Code patterns (106 lines)
└── QWEN.md                               # Qwen-Agent patterns (98 lines)
```

## Making Changes

### Step 1: Edit Templates

**Universal Content (affects all agents):**
- Edit files in `templates/shared/`
- Kubernetes: `templates/shared/kubernetes-migration.md`
- MCP: `templates/shared/mcp-integration.md`
- Build/test: `templates/shared/build-test-commands.md`
- Deployment: `templates/shared/deployment-workflows.md`

**Agent-Specific Content:**
- Edit `templates/base-template.md.j2`
- Look for `{% if agent_type == "claude" %}` sections
- Or `{% if agent_type == "qwen" %}` sections
- Or `{% if agent_type == "universal" %}` sections

### Step 2: Regenerate Files

```bash
cd /etc/nixos/docs
python3 generate-agent-instructions.py
```

Expected output:
```
✅ Successfully generated all 3 files

Generated files:
  • AGENTS.md (327 lines)
  • CLAUDE.md (106 lines)
  • QWEN.md (98 lines)
```

### Step 3: Validate Output

```bash
python3 validate-agent-files.py
```

Expected output:
```
✅ All files validated successfully
```

### Step 4: Review Changes

```bash
# See what changed
git diff AGENTS.md CLAUDE.md QWEN.md
```

### Step 5: Test Configuration

```bash
cd /etc/nixos
just test
```

### Step 6: Commit Changes

```bash
git add templates/ AGENTS.md CLAUDE.md QWEN.md docs/
git commit -m "docs: update agent instruction files

- Updated template/shared/[file].md
- Regenerated AGENTS.md, CLAUDE.md, QWEN.md
- See docs/plans/2026-03-08-agent-instruction-files-spec-design.md"
```

## Length Targets

| File | Current | Target | Status |
|------|---------|--------|--------|
| AGENTS.md | 327 lines | 500 lines | ✅ 65% |
| CLAUDE.md | 106 lines | 200 lines | ✅ 53% |
| QWEN.md | 98 lines | 200 lines | ✅ 49% |

## Separation of Concerns

### AGENTS.md (Universal Base Layer)
**Purpose:** Patterns applicable to ALL AI agents
**Includes:**
- Build & test commands
- Deployment workflows
- Kubernetes migration (universal patterns)
- MCP integration (protocol and standard tools)
- Project structure and profile system
- Hookify rules overview
- Service management

**Excludes:**
- Claude-specific tools (Serena, async agents)
- Qwen-specific tools (Qwen framework)

### CLAUDE.md (Claude Code Extensions)
**Purpose:** Claude Code-specific patterns only
**Includes:**
- Serena semantic tools
- Async agent launching
- Claude MCP integration specifics
- Claude workflow patterns

**Excludes:**
- Universal deployment workflows (in AGENTS.md)
- Universal Kubernetes patterns (in AGENTS.md)
- Qwen or other agent patterns

### QWEN.md (Qwen-Agent Extensions)
**Purpose:** Qwen-Agent-specific patterns only
**Includes:**
- Qwen framework patterns
- Qwen tool usage (function calling, code interpreter)
- Qwen MCP integration
- Qwen RAG patterns

**Excludes:**
- Universal deployment workflows (in AGENTS.md)
- Universal Kubernetes patterns (in AGENTS.md)
- Claude-specific patterns (in CLAUDE.md)

## Common Tasks

### Add Universal Content

1. Determine which shared file to edit:
   - Kubernetes: `templates/shared/kubernetes-migration.md`
   - MCP: `templates/shared/mcp-integration.md`
   - Build/test: `templates/shared/build-test-commands.md`
   - Deployment: `templates/shared/deployment-workflows.md`

2. Edit the shared file
3. Regenerate: `python3 generate-agent-instructions.py`
4. Validate: `python3 validate-agent-files.py`
5. Commit changes

### Add Claude-Specific Content

1. Edit `templates/base-template.md.j2`
2. Find `{% if agent_type == "claude" %}` section
3. Add content after `## Claude Code-Specific Features`
4. Regenerate and validate
5. Commit changes

### Add Qwen-Specific Content

1. Edit `templates/base-template.md.j2`
2. Find `{% if agent_type == "qwen" %}` section
3. Add content after `## Qwen-Agent-Specific Features`
4. Regenerate and validate
5. Commit changes

### Add New Agent Type

1. Create new agent type in `generate-agent-instructions.py`:
   ```python
   TITLES['newagent'] = 'NixOS Configuration - NewAgent Patterns'
   PURPOSES['newagent'] = '...'
   MAX_LINES['NEWAGENT.md'] = 200
   ```

2. Add section in `base-template.md.j2`:
   ```jinja2
   {% if agent_type == "newagent" %}
   ## NewAgent-Specific Features
   ...
   {% endif %}
   ```

3. Update validation script with required sections

4. Regenerate all files

## Troubleshooting

### Files Too Long

**Problem:** Generated file exceeds length target

**Solution:**
1. Check which sections are longest
2. Consider moving content to shared blocks (if universal)
3. Condense verbose explanations
4. Use "See AGENTS.md" references instead of duplicating

### Template Artifacts

**Problem:** Generated file contains `{{`, `}}`, `{%`, `%}`

**Solution:**
1. Check Jinja2 syntax in template
2. Ensure proper `{% endif %}` tags
3. Regenerate after fixing

### Missing Required Sections

**Problem:** Validation fails with "Missing required section"

**Solution:**
1. Check template has the section
2. Ensure section header matches exactly (e.g., `## Purpose`)
3. Regenerate after fixing

### Duplication Detected

**Problem:** Cross-file duplication warning

**Solution:**
1. If it's "See Also" sections, this is expected (structural similarity)
2. If it's actual content duplication:
   - Move to shared block if truly universal
   - Make agent-specific sections more distinct
   - Use references instead of duplicating

## Scripts Reference

### generate-agent-instructions.py

**Purpose:** Generate agent instruction files from templates

**Usage:**
```bash
cd /etc/nixos/docs
python3 generate-agent-instructions.py
```

**What it does:**
1. Loads Jinja2 templates
2. Renders for each agent type (universal, claude, qwen)
3. Writes to `/etc/nixos/`
4. Validates output against length targets
5. Reports success/failure

### validate-agent-files.py

**Purpose:** Validate generated files meet requirements

**Usage:**
```bash
cd /etc/nixos/docs
python3 validate-agent-files.py
```

**What it checks:**
- File length (must be under target)
- Required sections (Purpose, Quick Start, etc.)
- Template artifacts (none should remain)
- Duplicate sections (indicates template error)
- Common markdown issues (unclosed code blocks)

## Design Documentation

See the complete design document:
- `/etc/nixos/docs/plans/2026-03-08-agent-instruction-files-spec-design.md`

Contains:
- Detailed specification
- Template system architecture
- Implementation phases
- Success criteria
- Future considerations

## Getting Help

**For understanding the template system:**
1. Read this MAINTENANCE.md file
2. Read the design document
3. Examine existing templates in `templates/`
4. Run `generate-agent-instructions.py` with verbose output

**For Jinja2 template syntax:**
- Official docs: https://jinja.palletsprojects.com/
- Template syntax: `{{ variable }}`, `{% if %}`, `{% include %}`

**For validation issues:**
1. Run `validate-agent-files.py` to see specific errors
2. Check templates for syntax errors
3. Ensure all `{% if %}` have matching `{% endif %}`
4. Verify include files exist in `templates/shared/`

---

**Document Version:** 1.0
**Last Updated:** 2026-03-08
**Maintained by:** j_kro
