# NixOS Cluster Documentation Index

**Last Updated:** 2026-03-08 | **Cluster Version:** Pre-Kubernetes Migration | **Agent Files:** Template-based v1.0

This document provides a comprehensive index of all documentation for the NixOS cluster, including the ongoing Kubernetes migration.

---

## Quick Start

**For AI Agents (Claude Code, Cursor, Copilot, Qwen-Agent):**
1. Read `/etc/nixos/AGENTS.md` for universal cluster patterns (all agents)
2. Read agent-specific file: `CLAUDE.md` or `QWEN.md`
3. Check `/etc/nixos/ROADMAP.md` for current migration status

**For Human Operators:**
1. Read this index (DOCUMENTATION_INDEX.md)
2. Review relevant sections below
3. Use `just` commands for all operations

---

## Core Documentation

### 1. CLAUDE.md
**Purpose:** Claude Code agent guidelines and workspace overview
**Key Sections:**
- Workspace overview (multi-project structure)
- Project categories (active vs archive)
- Common patterns (NixOS flakes, MCP integration)
- Local infrastructure (AI gateway, GPU mining cluster)
- Git workflow and deployment methods
**When to Read:** First time using Claude Code on this cluster
**Location:** `/etc/nixos/CLAUDE.md`

### 2. AGENTS.md
**Purpose:** Comprehensive agent workflow guide for all AI agents
**Key Sections:**
- Build & test commands (prioritizes `just` commands)
- Code style guidelines (Nix language conventions)
- Project structure (flake outputs, directory layout)
- Profile system (hardware, role, network profiles)
- Host inventory (hardware specifications)
- Multi-host deployment (Colmena commands)
- **Kubernetes migration** (NEW - 9-week roadmap)
- MCP integration (Model Context Protocol)
- Service management and testing
**When to Read:** Any time an agent works on this cluster
**Location:** `/etc/nixos/AGENTS.md`

### 1. AGENTS.md
**Purpose:** Universal agent guidelines for ALL AI agents (Claude Code, Cursor, Copilot, Qwen-Agent, etc.)
**Key Sections:**
- Quick start for agents and humans
- Project overview (4-host cluster, resources, architecture)
- Build & test commands (just commands, CI/CD integration)
- Code style guidelines (Nix language conventions)
- Project structure (flake outputs, directory layout)
- Profile system (hardware, role, network profiles)
- Multi-host deployment (Colmena commands, storage verification)
- Kubernetes migration (9-week roadmap, architecture, commands)
- MCP integration (protocol, server configuration, troubleshooting)
- Hookify rules (deployment pattern enforcement)
- Service management and testing
- Documentation index
**Length:** 327 lines (template-generated)
**When to Read:** First time working on this cluster (universal patterns)
**Location:** `/etc/nixos/AGENTS.md`

### 2. CLAUDE.md
**Purpose:** Claude Code-specific patterns (extends AGENTS.md)
**Key Sections:**
- Quick start (refer to AGENTS.md for universal patterns)
- Serena semantic tools (find_symbol, find_referencing_symbols, get_symbols_overview)
- Async agent launching (parallel independent tasks)
- Claude MCP integration (Accept header requirements)
- Workflow patterns (Plan mode vs Editing mode)
- See also (links to AGENTS.md and other docs)
**Length:** 106 lines (template-generated)
**When to Read:** Using Claude Code on this cluster
**Location:** `/etc/nixos/CLAUDE.md`

### 3. QWEN.md
**Purpose:** Qwen-Agent-specific patterns (extends AGENTS.md)
**Key Sections:**
- Quick start (refer to AGENTS.md for universal patterns)
- Qwen framework (installation, tool usage)
- Function calling and code interpreter
- MCP integration (Qwen-specific configuration)
- RAG patterns (KnowledgeRetrieval)
- Memory and multi-turn conversations
- See also (links to AGENTS.md and other docs)
**Length:** 98 lines (template-generated)
**When to Read:** Using Qwen-Agent on this cluster
**Location:** `/etc/nixos/QWEN.md`

### 4. ROADMAP.md
**Purpose:** Complete Kubernetes migration plan (9-week timeline)
**Key Sections:**
- Executive summary (goals, approach, timeline)
- Current infrastructure assessment (cluster resources, 31 services)
- Migration goals and success criteria
- Technical architecture (full Kubernetes, not K3s)
- 7 implementation phases (Foundation → Cleanup)
- GPU passthrough strategy (NVIDIA + AMD mixed vendor)
- Risk assessment and mitigations
- Success metrics and next steps
**When to Read:** Before starting Kubernetes work, weekly during migration
**Location:** `/etc/nixos/ROADMAP.md`

---

## Operational Documentation

### Deployment Guides

#### DEPLOYMENT_COMPLETE.md
**Purpose:** Summary of completed cluster deployment work
**Contents:** Final status of cluster setup, storage configuration, service deployment
**When to Read:** Understanding current cluster state
**Location:** `/etc/nixos/DEPLOYMENT_COMPLETE.md`

#### switch-configuration-guide.md
**Purpose:** Guide for NixOS configuration switches
**Contents:** Step-by-step switch process, troubleshooting
**When to Read:** Performing system updates
**Location:** `/etc/nixos/switch-configuration-guide.md`

### Monitoring & Testing

#### COMPREHENSIVE_TEST_REPORT.md
**Purpose:** Results of comprehensive cluster testing
**Contents:** Test coverage, passed/failed tests, recommendations
**When to Read:** Verifying cluster health after changes
**Location:** `/etc/nixos/COMPREHENSIVE_TEST_REPORT.md`

#### TEST_REPORT.md
**Purpose:** Standard test results
**Contents:** Test execution, findings, issues
**When to Read:** Reviewing test outcomes
**Location:** `/etc/nixos/TEST_REPORT.md`

---

## Architecture & Design

### Network Architecture

#### network-analysis-report.md
**Purpose:** Detailed network configuration analysis
**Contents:** Tailscale VPN, Unbound DNS, service gateway
**When to Read:** Troubleshooting network issues
**Location:** `/etc/nixos/network-analysis-report.md`

### AI/ML Architecture

#### RAG_DESIGN.md
**Purpose:** RAG (Retrieval-Augmented Generation) system design
**Contents:** Architecture, data flow, implementation details
**When to Read:** Working on RAG features
**Location:** `/etc/nixos/RAG_DESIGN.md`

#### RAG_TEST_REPORT.md
**Purpose:** RAG system testing results
**Contents:** Test cases, performance metrics, issues
**When to Read:** Verifying RAG functionality
**Location:** `/etc/nixos/RAG_TEST_REPORT.md`

---

## Integration & Skills

### MCP Integration

#### SKILL_MCP_INTEGRATION_COMPLETE.md
**Purpose:** MCP (Model Context Protocol) integration summary
**Contents:** Server setup, tool configuration, testing results
**When to Read:** Setting up new MCP servers
**Location:** `/etc/nixos/SKILL_MCP_INTEGRATION_COMPLETE.md`

#### INTEGRATION_SUMMARY.md
**Purpose:** Overall integration status
**Contents:** Completed integrations, pending work
**When to Read:** Understanding cluster capabilities
**Location:** `/etc/nixos/INTEGRATION_SUMMARY.md`

### Skill Consolidation

#### SKILL-CONSOLIDATION-PLAN.md
**Purpose:** Plan for consolidating agent skills
**Contents:** Skill audit, consolidation strategy, timeline
**When to Read:** Managing agent skills
**Location:** `/etc/nixos/SKILL-CONSOLIDATION-PLAN.md`

#### SKILL-CONSOLIDATION-IMPLEMENTATION.md
**Purpose:** Implementation details for skill consolidation
**Contents:** Technical implementation, migration steps
**When to Read:** Executing skill consolidation
**Location:** `/etc/nixos/SKILL-CONSOLIDATION-IMPLEMENTATION.md`

#### SKILL-CONSOLIDATION-SUMMARY.md
**Purpose:** Summary of completed skill consolidation
**Contents:** Results, benefits, next steps
**When to Read:** Understanding skill changes
**Location:** `/etc/nixos/SKILL-CONSOLIDATION-SUMMARY.md`

---

## Insights & Analysis

### INSIGHTS.md
**Purpose:** Key insights from cluster operations
**Contents:** Lessons learned, optimization opportunities
**When to Read:** Looking for improvement ideas
**Location:** `/etc/nixos/INSIGHTS.md`

---

## Special Projects

### SPACEBOT_IMPLEMENTATION.md
**Purpose:** Spacebot project implementation details
**Contents:** Architecture, implementation, testing
**When to Read:** Working on Spacebot features
**Location:** `/etc/nixos/SPACEBOT_IMPLEMENTATION.md`

---

## Infrastructure Branch

### INFRABRANCH.md
**Purpose:** Infrastructure branch documentation
**Contents:** Branch strategy, merge workflow
**When to Read:** Managing infrastructure changes
**Location:** `/etc/nixos/INFRABRANCH.md`

---

## Kubernetes Migration

### Primary Documentation
**ROADMAP.md** (685 lines, comprehensive)
- Complete 9-week migration plan
- 7 implementation phases
- GPU passthrough strategy
- Service migration patterns
- Risk assessment and mitigations

**AGENTS.md** (updated with Kubernetes section)
- Kubernetes commands and workflows
- Service migration patterns
- NixOS Kubernetes configuration
- Troubleshooting guide

### Quick Reference

**Current Status:** Pre-migration (Planning Phase)
**Target:** Full upstream Kubernetes via `services.kubernetes`
**Timeline:** 9 weeks (estimated)
**Cluster Nodes:** 4 (Zephyr, Nexus, Forge, Sentry)

**Migration Phases:**
1. Foundation (Week 1-2) - Bootstrap cluster
2. Worker Nodes (Week 2-3) - Add all nodes
3. Stateful Services (Week 3-4) - Migrate databases
4. Stateless Services (Week 4-6) - Migrate applications
5. GPU Workloads (Week 6-7) - AI/ML with GPU passthrough
6. Monitoring (Week 7-8) - Re-enable Prometheus/Grafana
7. Cleanup (Week 8-9) - Remove old services, optimize

**Key Decisions:**
- **Full Kubernetes (not K3s)** - Maximum learning value
- **Flannel CNI** - VXLAN backend for pod networking
- **Longhorn** - Distributed block storage
- **NIXOS module** - Declarative Kubernetes config

---

## Workflow Documentation

### Justfile Commands

**Primary Commands:**
```bash
just test              # Verify configuration
just switch            # Apply to local host (auto-pauses mining)
just deploy            # Deploy to all cluster hosts
just sync              # Sync all nodes to current branch
just status            # Show cluster status
```

**Host-Specific:**
```bash
just zephyr            # Deploy to zephyr only
just nexus             # Deploy to nexus only
just forge             # Deploy to forge only
just sentry            # Deploy to sentry only
```

**CI/CD:**
```bash
just ci-local          # Run full CI pipeline locally
just health-check      # Cluster health check
just rollback          # Rollback to previous generation
```

### Critical Workflows

**Before Any Deployment:**
1. `just sync` - Ensure all nodes have same configuration
2. `just test` - Verify configuration builds
3. Check storage mounts on all nodes
4. Review hookify warnings

**Storage Verification:**
```bash
/data/@projects/infra/nixos/verify-cluster-storage.sh
```

**Git Workflow:**
1. Make changes
2. `git add` new files (Nix only packages git-tracked files!)
3. `git commit` with descriptive message
4. `just test` to verify
5. `just sync` to update all nodes
6. `just deploy` to apply changes

---

## Hookify Rules

11 hookify rules are configured in `/data/@projects/.claude/hookify-*.md` to prevent problematic behaviors:

**CRITICAL (blocks operations):**
- `block-ignore-build-errors` - Prevents error suppression

**HIGH Priority:**
- `warn-wrong-deploy-goals` - Ensures correct deploy goals for remote hosts
- `warn-git-sync-before-deploy` - Ensures cluster consistency

**MEDIUM Priority:**
- `warn-autogen-file-edits` - Prevents editing auto-generated files
- `warn-git-new-files` - Reminds to git add new files before rebuild
- `warn-cluster-operation-order` - Enforces test → deploy workflow
- `warn-storage-verification` - Ensures storage is mounted before deploy

**LOW Priority:**
- `warn-direct-nixos-rebuild` - Encourages using just commands
- `warn-long-running-tasks` - Encourages timeout/background flags
- `warn-mcp-tool-names` - Prevents incorrect MCP tool case
- `warn-mcp-accept-headers` - Ensures correct MCP headers

---

## Cluster Inventory

### Hosts

| Host | CPU | RAM | GPUs | Storage | Roles |
|------|-----|-----|------|---------|-------|
| **Zephyr** | AMD 5950X (32 cores) | 31GB | RTX 3090 + 3060 Ti | 1.85TB SSD | Control plane, workstation, gaming, VR, mining, AI |
| **Nexus** | AMD Zen (24 cores) | 46GB | 1x RTX 3060 Ti | 4.7TB (915GB + 3.6TB bcache0 + 224GB) | Storage, gaming, mining, AI |
| **Forge** | Intel Skylake (6 cores) | 15GB | 2x RTX 4060 + 2x RX 5700 XT | 446GB SSD | Multi-GPU mining, AI |
| **Sentry** | AMD Zen (16 cores) | 31GB | RX 5600 XT | 1.23TB (230GB SSD + 1TB HDD) | Mining, monitoring |

**Total Cluster Resources:**
- CPU: 78 cores
- RAM: 123GB
- GPUs: 7 total (5x NVIDIA + 2x AMD)
- Storage: ~8.4TB raw capacity

### Services

**Current Count:** 31 systemd services
**Target:** Migrate containerizable services to Kubernetes

**Service Categories:**
- AI/ML Services (5)
- Databases (2)
- Development Tools (3)
- File Sync (1)
- Gaming/Entertainment (4)
- Media (3)
- Monitoring (3)
- Networking (3)
- Productivity (2)
- Web Services (5)

---

## Documentation Maintenance

### When to Update Documentation

**Update IMMEDIATELY when:**
- Adding new services or features
- Changing deployment workflows
- Updating hardware configurations
- Discovering new patterns or anti-patterns
- Completing migration phases

**Review WEEKLY:**
- ROADMAP.md (during Kubernetes migration)
- AGENTS.md (for workflow improvements)
- Hookify rules (add new patterns as discovered)

### Documentation Standards

**Format:** Markdown
**Tone:** Clear, concise, actionable
**Audience:** AI agents and human operators
**Version Control:** Git-tracked in `/etc/nixos`

**Quality Checklist:**
- [ ] Clear purpose statement
- [ ] Accurate technical details
- [ ] Actionable instructions
- [ ] Examples where helpful
- [ ] Cross-references to related docs
- [ ] Date stamp for last update

---

## Getting Help

### For AI Agents
1. Read relevant documentation sections
2. Check hookify rules for patterns
3. Use `just test` before making changes
4. Follow systematic debugging process (AGENTS.md)

### For Humans
1. Start with DOCUMENTATION_INDEX.md (this file)
2. Review relevant sections above
3. Check ROADMAP.md for current status
4. Use `just status` to see cluster state
5. Review logs: `journalctl -xe` for errors

### Common Tasks

**Deploy configuration:**
```bash
just sync && just test && just deploy
```

**Check cluster health:**
```bash
just status
just health-check
/data/@projects/infra/nixos/verify-cluster-storage.sh
```

**View service logs:**
```bash
journalctl -u <service-name> -f
systemctl status <service-name>
```

**Debug Kubernetes (during migration):**
```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl logs <pod-name> -n <namespace>
```

---

## Agent Instruction Files System

### Template-Based Generation (NEW - 2026-03-08)

#### MAINTENANCE.md
**Purpose:** Guide for maintaining agent instruction files
**Contents:**
- Template system architecture
- How to make changes (edit templates, regenerate, validate)
- Separation of concerns (AGENTS.md vs CLAUDE.md vs QWEN.md)
- Common tasks (add universal content, add agent-specific content)
- Troubleshooting and script reference
**When to Read:** When updating agent instruction files
**Location:** `/etc/nixos/docs/MAINTENANCE.md`

#### Agent Instruction Files Specification (Design Document)
**Purpose:** Complete design specification for template-based generation system
**Contents:**
- File structure and purpose
- Content boundaries and separation of concerns
- Template-based generation system design
- Length guidelines and best practices
- Implementation plan and success criteria
**When to Read:** Understanding the agent instruction file architecture
**Location:** `/etc/nixos/docs/plans/2026-03-08-agent-instruction-files-spec-design.md`

### Agent Instruction Files

#### AGENTS.md (Universal - Template Generated)
**Purpose:** Universal patterns for ALL AI agents
**Length:** 327 lines (target: 500 lines)
**Includes:** Build commands, deployment, Kubernetes, MCP, profiles, testing
**Location:** `/etc/nixos/AGENTS.md`

#### CLAUDE.md (Claude Code - Template Generated)
**Purpose:** Claude Code-specific patterns (extends AGENTS.md)
**Length:** 106 lines (target: 200 lines)
**Includes:** Serena tools, async agents, Claude MCP, workflow patterns
**Location:** `/etc/nixos/CLAUDE.md`

#### QWEN.md (Qwen-Agent - Template Generated)
**Purpose:** Qwen-Agent-specific patterns (extends AGENTS.md)
**Length:** 98 lines (target: 200 lines)
**Includes:** Qwen framework, function calling, MCP integration, RAG
**Location:** `/etc/nixos/QWEN.md`

---

## Change Log

### 2026-03-08
- Created DOCUMENTATION_INDEX.md
- Updated AGENTS.md with Kubernetes migration section
- Updated CLAUDE.md to prioritize just commands
- Created ROADMAP.md (685 lines, comprehensive Kubernetes plan)
- Created 11 hookify rules for workflow enforcement
- Fixed cluster storage issues (Nexus 3.8TB activated)

### Previous Changes
See individual documentation files for detailed change history

---

**Document Owner:** j_kro
**Cluster Version:** Pre-Kubernetes Migration (Planning Phase)
**Next Review:** After Phase 1 completion (Week 2)
