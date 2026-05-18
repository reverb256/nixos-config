---
name: agent-dispatch
description: Routes tasks to the appropriate AI agent (Kelos, OMP, Claude Code) based on task type, complexity, and required tooling.
type: devops
version: "1.0.0"
---

# Agent Dispatch

Routes work to the most appropriate AI agent based on task characteristics.

## Agents Overview

| Agent | Strengths | Best For |
|-------|-----------|----------|
| **Kelos** | Fast, cheap, NixOS-native | Simple bugfixes, config tweaks, documentation |
| **OMP** | ast-grep, LSP, structural editing | Multi-file refactors, renames, codebase-wide changes |
| **Claude Code** | Deep reasoning, complex features | Complex features, architecture changes, TDD workflows |

## Dispatch Routing Decision Tree

```
Task received
    |
    v
Is it a structural refactor? (rename across files, ast-grep pattern)
    |
    +-- YES --> Route to OMP
    |
    +-- NO
        |
        v
    Is it a simple bugfix or config change?
        |
        +-- YES --> Route to Kelos
        |
        +-- NO
            |
            v
        Is it a complex feature requiring deep reasoning?
            |
            +-- YES --> Route to Kelos with Claude Code (if available)
            |
            +-- NO --> Route to Kelos
```

## OMP Routing Rules

Route to **OMP** when the task involves:

- **Structural refactors** — ast-grep pattern matching, AST-level transformations
- **Multi-file rename/refactor** — renaming symbols, functions, or variables across multiple files
- **LSP-aware operations** — tasks that benefit from language server intelligence
- **Codebase-wide pattern changes** — applying the same transformation to many files

Route to **Kelos** when the task involves:

- **Simple bugfixes** — single-file fixes, typo corrections, small logic changes
- **Config tweaks** — NixOS module adjustments, K8s manifest updates
- **Documentation** — updating docs, READMEs, AGENTS.md
- **Quick queries** — codebase exploration, status checks

Route to **Kelos with Claude Code** when the task involves:

- **Complex features** — multi-layer changes (DB + API + UI)
- **Architecture changes** — design decisions, new module patterns
- **TDD workflows** — test-first development with complex test suites

## OMP Usage Examples

### Example 1: Multi-file symbol rename

```
User: "Rename all instances of 'oldServiceName' to 'newServiceName' across the codebase"
→ OMP skill triggers
→ Uses LSP/ast-grep to find and rename all occurrences safely
```

### Example 2: Structural refactor with ast-grep

```
User: "Convert all deprecated React class components to functional components in src/"
→ OMP skill triggers
→ Uses ast-grep to match class component patterns and transform to functional components
```

### Example 3: Codebase-wide pattern change

```
User: "Replace all console.log calls with the new logger utility across all services"
→ OMP skill triggers
→ Uses pattern matching to find and replace across multiple directories
```

## Kelos Usage Examples

### Example 1: Simple bugfix

```
User: "Fix the typo in the Caddy route for grafana.lan"
→ Kelos handles it directly
→ Single-file edit, fast turnaround
```

### Example 2: Config change

```
User: "Add port 32200 to the firewall allowed list on Nexus"
→ Kelos handles it directly
→ Uses lib.mkOptionDefault pattern, validates with just check
```

## Kelos + Claude Code Usage Examples

### Example: Complex feature

```
User: "Add a new monitoring dashboard with custom Prometheus metrics and Grafana panel"
→ Kelos orchestrates with Claude Code
→ Claude Code handles the complex multi-layer implementation
→ Kelos manages the NixOS integration and deployment
```

## Dispatch Guidelines

| Task Type | Agent | Reason |
|-----------|-------|--------|
| Rename symbol across 5+ files | OMP | LSP/ast-grep precision |
| Fix single-line bug | Kelos | Fast, cheap |
| Refactor module structure | OMP | AST-level understanding |
| Add new NixOS module | Kelos | Follows existing patterns |
| Build new API endpoint | Kelos + Claude Code | Complex, multi-layer |
| Update documentation | Kelos | Simple, straightforward |
| Migrate deprecated syntax | OMP | Pattern matching across files |
| Fix SSH/firewall config | Kelos | Safety-critical, needs NixOS expertise |
