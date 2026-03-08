# Agent Instruction Files Specification - Design Document

**Date:** 2026-03-08
**Author:** j_kro
**Status:** Design Approved - Pending Implementation
**Related Files:** `/etc/nixos/AGENTS.md`, `/etc/nixos/CLAUDE.md`

---

## Executive Summary

This specification defines a standardized framework for agent instruction files (AGENTS.md, CLAUDE.md, QWEN.md) in the NixOS cluster configuration. The current implementation has significant issues:

- **Massive duplication**: ~415 lines shared between AGENTS.md and CLAUDE.md
- **Unclear boundaries**: Universal content mixed with agent-specific patterns
- **Excessive length**: AGENTS.md (881 lines), CLAUDE.md (887 lines)
- **Maintenance burden**: Updates require manual synchronization

**Solution**: Template-based generation system with clear separation of concerns:
- **AGENTS.md** (400-500 lines): Universal patterns for all agents
- **CLAUDE.md** (150-200 lines): Claude Code-specific extensions
- **QWEN.md** (150-200 lines): Qwen-Agent-specific extensions

This approach provides single source of truth, eliminates duplication, and makes maintenance sustainable.

---

## 1. File Structure and Purpose

### Overview

The agent instruction file system consists of a **universal base layer** plus **agent-specific extensions**. This hierarchical design eliminates duplication while maintaining specialization for different AI agents.

### File Types

#### AGENTS.md (Universal Base Layer)

- **Purpose**: Patterns and workflows applicable to ALL AI agents working on this NixOS cluster
- **Target Audience**: Claude Code, Cursor, Copilot, OpenCode, Qwen-Agent, and any future agent
- **Length Target**: 400-500 lines
- **Content**: Universal workflows, cluster architecture, deployment patterns, testing procedures

#### CLAUDE.md (Claude Code Extensions)

- **Purpose**: Claude Code-specific patterns that extend the universal base
- **Target Audience**: Claude Code agents only
- **Length Target**: 150-200 lines
- **Content**: Serena semantic tools, async agent launching, Claude MCP usage patterns

#### QWEN.md (Qwen-Agent Extensions)

- **Purpose**: Qwen-Agent-specific patterns that extend the universal base
- **Target Audience**: Qwen-Agent instances only
- **Length Target**: 150-200 lines
- **Content**: Qwen framework patterns, Qwen MCP integration, Qwen-specific tool usage

### Relationship Diagram

```
AGENTS.md (universal base)
    ├── extends to → CLAUDE.md (Claude-specific additions)
    └── extends to → QWEN.md (Qwen-specific additions)
```

Each agent-specific file assumes the universal base is loaded first, then adds its specialized content.

---

## 2. Content Boundaries and Separation of Concerns

### AGENTS.md (Universal Base Layer) - INCLUDES

- NixOS/Flake build and test procedures (just commands, nixos-rebuild)
- Cluster architecture overview (4 hosts, roles, resources)
- Project structure (flake outputs, directory layout)
- Profile system explanation (hardware, role, network profiles)
- Deployment workflows (Colmena, multi-host deployment)
- Git workflow and branch strategies
- Code style guidelines (Nix language conventions)
- Service management (systemd, monitoring, logs)
- Testing procedures (health checks, verification)
- Hookify rules overview
- **Universal Kubernetes migration patterns** (architecture, phases, timelines)
- **Universal MCP integration patterns** (protocol, standard tools)

### AGENTS.md - EXCLUDES

- Claude-specific tools (Serena, async agents)
- Qwen-specific tools (Qwen framework patterns)
- Agent-specific MCP usage patterns

### CLAUDE.md (Claude Code Extensions) - INCLUDES

- Serena semantic tool patterns (find_symbol, find_referencing_symbols, etc.)
- Async agent launching patterns (Agent tool usage)
- Claude Code workflow patterns (Plan mode, editing vs interactive)
- Claude MCP integration specifics
- Claude Code output style modes
- Claude-specific build/test patterns (if different from universal)

### CLAUDE.md - EXCLUDES

- Universal deployment workflows (in AGENTS.md)
- Universal Kubernetes patterns (in AGENTS.md)
- Universal MCP concepts (in AGENTS.md)
- Qwen or other agent patterns

### QWEN.md (Qwen-Agent Extensions) - INCLUDES

- Qwen-Agent framework patterns
- Qwen tool usage patterns (function calling, code interpreter)
- Qwen MCP integration specifics
- Qwen RAG patterns
- Qwen memory/agent chat patterns

### QWEN.md - EXCLUDES

- Universal deployment workflows (in AGENTS.md)
- Universal Kubernetes patterns (in AGENTS.md)
- Universal MCP concepts (in AGENTS.md)
- Claude-specific patterns (in CLAUDE.md)

### Key Principle: Universal vs Agent-Specific

- **Universal**: Applies to ALL agents regardless of their capabilities
- **Agent-Specific**: Only applies to agents with those specific features

### Example: MCP Integration Separation

```markdown
# AGENTS.md (Universal)
This cluster uses MCP (Model Context Protocol) for tool integration.
MCP servers are configured in `/etc/nixos/mcp-servers/` and follow the
standard JSON-RPC 2.0 specification. See ROADMAP.md for cluster-wide
MCP architecture.

# CLAUDE.md (Claude-Specific)
When using MCP with Claude Code, always set Accept headers to
`application/json, text/event-stream` for ZAI MCP servers to avoid
400 Bad Request errors. See hookify.warn-mcp-accept-headers rule.

# QWEN.md (Qwen-Specific)
Qwen-Agent's MCP integration requires the `qwen-agent[mcp]` extra:
`pip install -U 'qwen-agent[mcp]'`. Configure servers in
`.qwenrc.json` using the Qwen MCP configuration format.
```

---

## 3. Template-Based Generation System

### Problem with Current Files

The current AGENTS.md and CLAUDE.md have:
- ~277 lines of identical Kubernetes migration content
- ~138 lines of identical MCP integration content
- ~415 total lines of duplication

This occurs because:
- Markdown doesn't support native includes
- Manual updates lead to divergence
- No single source of truth

### Solution: Template-Based Generation

#### Directory Structure

```
/etc/nixos/docs/
├── templates/
│   ├── AGENTS-base.md.j2                  (Jinja2 template - universal base)
│   ├── CLAUDE-extensions.md.j2             (Jinja2 template - Claude-specific)
│   ├── QWEN-extensions.md.j2               (Jinja2 template - Qwen-specific)
│   └── shared/
│       ├── kubernetes-migration.md         (Shared content block)
│       ├── mcp-integration.md              (Shared content block)
│       ├── deployment-workflows.md         (Shared content block)
│       ├── build-test-commands.md          (Shared content block)
│       └── testing-procedures.md           (Shared content block)
│
├── generate-agent-instructions.py          (Generation script)
│
└── plans/
    └── 2026-03-08-agent-instruction-files-spec-design.md  (This document)

/etc/nixos/ (Generated outputs)
├── AGENTS.md                               (Generated from templates)
├── CLAUDE.md                               (Generated from templates)
└── QWEN.md                                 (Generated from templates)
```

#### Template Format (Jinja2)

```markdown
# {{ title }}

## Purpose
{{ purpose }}

## Quick Start
{% if agent_type == "universal" %}
```bash
just test              # Verify configuration
just switch            # Apply to local host
just deploy            # Deploy to all cluster hosts
```
{% endif %}

{% if agent_type in ["universal", "claude"] %}
## Build & Test Commands
{% include 'shared/build-test-commands.md' %}
{% endif %}

{% if agent_type == "claude" %}
## Claude Code-Specific Features
### Serena Semantic Tools
...

### Async Agent Launching
...
{% endif %}

{% if agent_type == "qwen" %}
## Qwen-Agent-Specific Features
### Qwen Framework Patterns
...

### Qwen MCP Integration
...
{% endif %}

{% include 'shared/kubernetes-migration.md' %}
{% include 'shared/mcp-integration.md' %}
{% include 'shared/deployment-workflows.md' %}
```

#### Generation Script

```python
#!/usr/bin/env python3
"""Generate agent instruction files from templates."""

import jinja2
from pathlib import Path

# Configuration
TEMPLATE_DIR = Path(__file__).parent / 'templates'
OUTPUT_DIR = Path('/etc/nixos')
MAX_LINES = {
    'universal': 500,
    'claude': 200,
    'qwen': 200
}

def generate_file(agent_type: str, output_path: Path):
    """Generate a specific agent instruction file."""
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(TEMPLATE_DIR),
        trim_blocks=True,
        lstrip_blocks=True
    )

    template = env.get_template('base-template.md.j2')
    content = template.render(
        agent_type=agent_type,
        title=TITLES[agent_type],
        purpose=PURPOSES[agent_type]
    )

    output_path.write_text(content)
    print(f"Generated {output_path.name} ({len(content.splitlines())} lines)")

def main():
    """Generate all agent instruction files."""
    print("Generating agent instruction files...")

    generate_file('universal', OUTPUT_DIR / 'AGENTS.md')
    generate_file('claude', OUTPUT_DIR / 'CLAUDE.md')
    generate_file('qwen', OUTPUT_DIR / 'QWEN.md')

    print("\n✅ All files generated successfully")
    print("Run 'just test' to verify configuration")

if __name__ == '__main__':
    main()
```

### Workflow

1. **Edit templates** when content needs changing
2. **Run generation script** (`/etc/nixos/docs/generate-agent-instructions.py`)
3. **Verify output** (check length, sections, no duplication)
4. **Commit both templates and generated files** to git
5. **Deploy** with `just deploy` to update cluster

### Benefits

- ✅ Single source of truth for shared content
- ✅ No manual duplication
- ✅ Easy to add new agent types (just add new template variables)
- ✅ Generated files are still readable markdown (no runtime dependencies)
- ✅ Can validate structure automatically

---

## 4. Length Guidelines and Best Practices

### Length Targets

| File | Target Lines | Current Lines | Reduction Needed |
|------|--------------|---------------|------------------|
| AGENTS.md | 400-500 | 881 | -381 to -481 lines (43-55%) |
| CLAUDE.md | 150-200 | 887 | -687 to -737 lines (77-83%) |
| QWEN.md | 150-200 | 0 (new file) | N/A |

### Section Length Limits

- **Individual sections**: 50-100 lines maximum
- **Subsections**: 20-40 lines maximum
- **Code examples**: 10-30 lines maximum
- **Break long sections** into subsections with clear headings
- **Use expandable details** for optional or advanced content

### Content Density Principles

1. **Prioritize actionable instructions** over explanations
2. **Link to external docs** rather than duplicating content
3. **Use code examples** over verbose descriptions
4. **Remove redundancy** within sections
5. **Delete outdated content** aggressively

### Organizational Principles

1. **Put most-used content first**
2. **Group related concepts together**
3. **Use consistent heading hierarchy** (## → ### → ####)
4. **Include table of contents** for files >300 lines
5. **Use bullet lists** for readability
6. **Add code blocks** for all command examples

### Maintenance Guidelines

**Weekly** (during Kubernetes migration):
- Regenerate files from templates
- Validate output
- Commit if changes

**Monthly**:
- Review all sections for relevance
- Update outdated patterns
- Check for new duplication

**Quarterly**:
- Comprehensive review of all content
- Remove deprecated sections
- Update examples and commands
- Refactor if needed

---

## 5. Template Structure and Content Organization

### Template Hierarchy

```markdown
# {{ title }}

## Purpose
<!-- 3-5 lines explaining what this file is for -->

## Quick Start
<!-- Top 5 most common commands/patterns -->

{% if agent_type == "universal" %}
## Project Overview
<!-- Cluster architecture, 4 hosts, roles -->
{% endif %}

{% if agent_type in ["universal", "claude"] %}
## Build & Test Commands
{% include 'shared/build-test-commands.md' %}
{% endif %}

{% if agent_type == "claude" %}
## Claude Code-Specific Features
### Serena Semantic Tools
<!-- find_symbol, find_referencing_symbols, etc. -->

### Async Agent Launching
<!-- Agent tool usage patterns -->

### Claude Code Workflow Patterns
<!-- Plan mode, editing vs interactive -->
{% endif %}

{% if agent_type == "qwen" %}
## Qwen-Agent-Specific Features
### Qwen Framework Patterns
<!-- Qwen architecture patterns -->

### Qwen Tool Usage
<!-- Function calling, code interpreter -->

### Qwen MCP Integration
<!-- Qwen-specific MCP configuration -->
{% endif %}

{% include 'shared/kubernetes-migration.md' %}
{% include 'shared/mcp-integration.md' %}
{% include 'shared/deployment-workflows.md' %}
```

### Section Organization Principles

1. **Universal First**: AGENTS.md establishes base patterns
2. **Progressive Enhancement**: Agent-specific files build on universal
3. **Shared Blocks**: Common content in `templates/shared/`
4. **Clear Boundaries**: Each section has a single, clear purpose
5. **No Cross-References**: Don't reference content meant for other agent types

### Shared Content Blocks

**`templates/shared/kubernetes-migration.md`** (~277 lines):
- Current infrastructure assessment
- Migration goals and success criteria
- Technical architecture (full Kubernetes, not K3s)
- 7 implementation phases
- GPU passthrough strategy
- Risk assessment and mitigations

**`templates/shared/mcp-integration.md`** (~138 lines):
- MCP overview and purpose
- Cluster-wide MCP architecture
- Standard MCP tools and servers
- Configuration patterns
- Troubleshooting common issues

**`templates/shared/deployment-workflows.md`** (~100 lines):
- Multi-host deployment with Colmena
- Git workflow and branching
- Profile-based host configuration
- Rollback procedures
- Storage verification

**`templates/shared/build-test-commands.md`** (~80 lines):
- Justfile commands (primary workflow)
- Legacy nixos-rebuild commands
- CI/CD integration
- Testing procedures

---

## 6. Validation and Maintenance

### Automated Validation Script

```python
#!/usr/bin/env python3
"""Validate generated agent instruction files."""

import re
from pathlib import Path
from typing import List, Dict

# Configuration
MAX_LINES = {
    'AGENTS.md': 500,
    'CLAUDE.md': 200,
    'QWEN.md': 200
}

REQUIRED_SECTIONS = {
    'AGENTS.md': ['Purpose', 'Quick Start', 'Build & Test Commands', 'Project Overview'],
    'CLAUDE.md': ['Purpose', 'Claude Code-Specific Features'],
    'QWEN.md': ['Purpose', 'Qwen-Agent-Specific Features']
}

def validate_file(file_path: Path) -> List[str]:
    """Validate a single agent instruction file."""
    content = file_path.read_text()
    lines = content.split('\n')

    errors = []

    # Check length
    if len(lines) > MAX_LINES.get(file_path.name, 500):
        errors.append(
            f"❌ File too long: {len(lines)}/{MAX_LINES[file_path.name]} lines "
            f"(exceeds target by {len(lines) - MAX_LINES[file_path.name]} lines)"
        )

    # Check required sections
    for section in REQUIRED_SECTIONS.get(file_path.name, []):
        if f"## {section}" not in content:
            errors.append(f"❌ Missing required section: {section}")

    # Check for duplicate sections (indicates template error)
    section_counts = {}
    for line in lines:
        if line.startswith('## '):
            section = line[3:]
            section_counts[section] = section_counts.get(section, 0) + 1

    for section, count in section_counts.items():
        if count > 1:
            errors.append(f"⚠️  Duplicate section: '{section}' ({count} times)")

    # Check for common markdown issues
    if content.count('```') % 2 != 0:
        errors.append("❌ Unclosed code block (odd number of ``` markers)")

    # Check for TODO/FIXME markers
    todo_pattern = re.compile(r'{{\s*(TODO|FIXME|XXX)\s*}}')
    todos = todo_pattern.findall(content)
    if todos:
        errors.append(f"⚠️  Found {len(todos)} TODO/FIXME markers in generated file")

    return errors

def check_duplication(files: List[Path]) -> List[str]:
    """Check for duplicate content across files."""
    errors = []
    content_map = {}

    for file_path in files:
        content = file_path.read_text()
        content_map[file_path.name] = content

    # Check for duplicate sections (heuristic: 20+ consecutive identical lines)
    for i, (file1, content1) in enumerate(content_map.items()):
        for file2, content2 in list(content_map.items())[i+1:]:
            lines1 = content1.split('\n')
            lines2 = content2.split('\n')

            duplicate_blocks = 0
            for start_idx in range(len(lines1) - 20):
                block1 = '\n'.join(lines1[start_idx:start_idx+20])
                for start_idx2 in range(len(lines2) - 20):
                    block2 = '\n'.join(lines2[start_idx2:start_idx2+20])
                    if block1 == block2:
                        duplicate_blocks += 1

            if duplicate_blocks > 5:
                errors.append(
                    f"⚠️  Potential duplication between {file1} and {file2}: "
                    f"~{duplicate_blocks * 20} lines"
                )

    return errors

def main():
    """Validate all agent instruction files."""
    files = [
        Path('/etc/nixos/AGENTS.md'),
        Path('/etc/nixos/CLAUDE.md'),
        Path('/etc/nixos/QWEN.md')
    ]

    print("🔍 Validating agent instruction files...\n")

    all_errors = []

    for file_path in files:
        if not file_path.exists():
            print(f"⚠️  {file_path.name} does not exist yet (skipping)")
            continue

        print(f"Validating {file_path.name}...")
        errors = validate_file(file_path)

        if errors:
            all_errors.extend(errors)
            for error in errors:
                print(f"  {error}")
        else:
            print(f"  ✅ {file_path.name} is valid")

    # Check for duplication
    print("\nChecking for cross-file duplication...")
    dup_errors = check_duplication([f for f in files if f.exists()])
    for error in dup_errors:
        print(f"  {error}")
        all_errors.append(error)

    # Summary
    print("\n" + "="*60)
    if all_errors:
        print(f"❌ Validation failed: {len(all_errors)} errors found")
        return 1
    else:
        print("✅ All files validated successfully")
        return 0

if __name__ == '__main__':
    exit(main())
```

### Maintenance Workflow

**Weekly** (during Kubernetes migration):
```bash
cd /etc/nixos/docs
python3 generate-agent-instructions.py  # Regenerate from templates
python3 validate-agent-files.py         # Validate output
git add templates/ AGENTS.md CLAUDE.md QWEN.md
git commit -m "docs: update agent instruction files from templates"
```

**Quarterly**:
1. Review all sections for relevance
2. Update outdated patterns
3. Remove deprecated content
4. Refactor if structure needs improvement
5. Update this design document if needed

### When Adding New Agent Type

1. Create agent-specific extension template (`templates/{AGENT}-extensions.md.j2`)
2. Add agent_type variable to generation script
3. Add entry to MAX_LINES, REQUIRED_SECTIONS in validation script
4. Regenerate all files
5. Validate and test

---

## 7. Implementation Plan

### Phase 1: Create Template System (Week 1, Days 1-3)

**Tasks**:
1. Create `/etc/nixos/docs/templates/` directory structure
2. Extract shared content blocks from existing AGENTS.md and CLAUDE.md
3. Create Jinja2 templates:
   - `templates/base-template.md.j2` (main template)
   - `templates/shared/kubernetes-migration.md`
   - `templates/shared/mcp-integration.md`
   - `templates/shared/deployment-workflows.md`
   - `templates/shared/build-test-commands.md`
4. Write `generate-agent-instructions.py` script
5. Test generation locally

**Success Criteria**:
- ✅ Templates generate valid markdown
- ✅ Generated files are readable
- ✅ No syntax errors in Jinja2 templates

### Phase 2: Refactor Existing Content (Week 1, Days 3-5)

**Tasks**:
1. Audit current AGENTS.md and CLAUDE.md:
   - Identify all duplicate sections
   - Categorize content: universal vs Claude-specific vs Qwen-specific
   - Mark content for deletion/move
2. Move shared content to `templates/shared/`
3. Create clean templates with proper separation:
   - `templates/AGENTS-base.md.j2` (universal)
   - `templates/CLAUDE-extensions.md.j2` (Claude-specific)
   - `templates/QWEN-extensions.md.j2` (Qwen-specific)
4. Remove Claude-specific content from AGENTS.md
5. Remove universal content from CLAUDE.md

**Success Criteria**:
- ✅ Zero duplicate sections between files
- ✅ All content properly categorized
- ✅ Templates follow separation of concerns

### Phase 3: Generate and Validate (Week 2, Days 1-3)

**Tasks**:
1. Run generation script to produce new AGENTS.md, CLAUDE.md, QWEN.md
2. Validate output:
   - Check length targets (AGENTS.md < 500 lines, CLAUDE.md < 200 lines, QWEN.md < 200 lines)
   - Verify required sections present
   - Check for duplicate sections
   - Run validation script
3. Compare against originals for completeness:
   - No critical content lost
   - All links valid
   - All code examples working
4. Test with actual agent workflows:
   - Have Claude Code read new files
   - Verify agents can follow instructions
   - Check that all commands work

**Success Criteria**:
- ✅ All validation checks pass
- ✅ Length targets met
- ✅ Zero duplication
- ✅ All content preserved and organized

### Phase 4: Deploy and Document (Week 2, Days 3-5)

**Tasks**:
1. Commit templates and generated files:
   ```bash
   git add templates/ AGENTS.md CLAUDE.md QWEN.md
   git commit -m "docs: implement template-based agent instruction files

   - Add template-based generation system
   - Refactor AGENTS.md (881 → ~450 lines)
   - Refactor CLAUDE.md (887 → ~175 lines)
   - Create QWEN.md (~175 lines)
   - Eliminate 415 lines of duplication
   - See docs/plans/2026-03-08-agent-instruction-files-spec-design.md"
   ```
2. Update DOCUMENTATION_INDEX.md with new structure
3. Create MAINTENANCE.md with workflow documentation
4. Add CI check to validate generated files (optional)
5. Deploy to cluster with `just deploy`

**Success Criteria**:
- ✅ All files committed to git
- ✅ Documentation updated
- ✅ Cluster deploys successfully
- ✅ Agents can use new files immediately

### Risk Mitigation

**Risk**: Generation script breaks existing workflows
**Mitigation**: Keep backup of original files, test thoroughly before deploying

**Risk**: Content lost during refactoring
**Mitigation**: Audit trail of all changes, diff before/after, manual review

**Risk**: Template system adds complexity
**Mitigation**: Simple Jinja2 templates, clear documentation, automate generation

**Risk**: Agents confused by new file structure
**Mitigation**: Clear purpose statements in each file, maintain familiar sections

---

## 8. Success Criteria

The implementation is successful when:

- ✅ **AGENTS.md** < 500 lines (current: 881 lines)
- ✅ **CLAUDE.md** < 200 lines (current: 887 lines)
- ✅ **QWEN.md** < 200 lines (current: 0 lines, new file)
- ✅ **Zero duplicate content** between files (current: ~415 lines duplicated)
- ✅ **All agents** can work with their respective files
- ✅ **Single source of truth** in templates/
- ✅ **Validation script** passes without errors
- ✅ **Documentation** updated (DOCUMENTATION_INDEX.md, MAINTENANCE.md)
- ✅ **Cluster deploys** successfully with new files
- ✅ **Maintenance workflow** tested and documented

---

## 9. Future Considerations

### Extensibility

- New agent types can be added by creating new extension templates
- Shared content blocks can be added as needed
- Template system supports arbitrary complexity

### Automation

- CI/CD check to validate generated files match templates
- Automatic regeneration on template changes
- Pre-commit hooks to catch manual edits to generated files

### Documentation

- Consider creating AGENT-INSTRUCTIONS-TUTORIAL.md for new contributors
- Add examples of common patterns
- Document template editing workflow

### Tooling

- Could develop VS Code extension for template editing
- Could add web-based preview of generated files
- Could integrate with documentation generators

---

## Appendix A: File Name Standard

**IMPORTANT**: The filename **AGENTS.md** is part of the established cluster documentation standard and must not be changed.

```
✅ CORRECT:  AGENTS.md
❌ INCORRECT: AGENT-INSTRUCTIONS.md
❌ INCORRECT: AGENT_GUIDELINES.md
❌ INCORRECT: AGENTS_GUIDE.md
```

This naming convention is referenced in:
- DOCUMENTATION_INDEX.md
- Multiple workflow documentation files
- Agent tool configurations

Changing the filename would break existing integrations and references.

---

## Appendix B: Related Files

- `/etc/nixos/DOCUMENTATION_INDEX.md` - Centralized documentation navigation
- `/etc/nixos/ROADMAP.md` - Kubernetes migration plan (referenced by agent files)
- `/etc/nixos/CLAUDE.md` - Current Claude Code-specific patterns (to be refactored)
- `/etc/nixos/AGENTS.md` - Current universal patterns (to be refactored)
- `/data/@projects/CLAUDE.md` - Workspace-level Claude Code patterns
- `/data/@projects/.claude/hookify-*.md` - Workflow enforcement rules

---

## Appendix C: References

- NixOS Documentation: https://nixos.org/manual/nixos/stable/
- Nix Flakes: https://nixos.wiki/wiki/Flakes
- Jinja2 Templates: https://jinja.palletsprojects.com/
- Claude Code Documentation: https://claude.ai/code
- Qwen-Agent: https://github.com/QwenLM/Qwen-Agent

---

**Document Version**: 1.0
**Last Updated**: 2026-03-08
**Status**: Design Approved - Ready for Implementation
**Next Step**: Begin Phase 1 - Create Template System
