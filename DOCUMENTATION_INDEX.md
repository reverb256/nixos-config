# NixOS Cluster Documentation Index

**Last Updated:** 2026-03-13 | **Cluster Version:** Phase 1 Complete (K8s v1.35.0 running) | **Agent Files:** Template-based v1.0

This document provides a comprehensive index of all documentation for the NixOS cluster, including the ongoing Kubernetes migration.

---

## Quick Start

**For AI Agents (Claude Code, Cursor, Copilot, Qwen-Agent):**
1. Read `/etc/nixos/AGENTS.md` for universal cluster patterns (all agents)
2. Read agent-specific file: `CLAUDE.md` or `QWEN.md`
3. Check `/etc/nixos/ROADMAP.md` for current migration status

**For Human Operators:**
1. **First:** STATUS.md for real-time cluster state
2. Read this index (DOCUMENTATION_INDEX.md) for full documentation catalog
3. Use `just` commands for all operations

---

## Core Documentation

### STATUS.md (NEW - 2026-03-13)
**Purpose:** Real-time cluster health and migration progress snapshot
**Key Sections:**
- Cluster health overview (K8s, nodes, GPU, storage)
- Migration progress by phase
- Known issues and next actions
- Quick commands for cluster management
**When to Read:** Checking current cluster state before making changes
**Location:** `/etc/nixos/STATUS.md`
**Refresh:** Run `just status` or manually update this file

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

### Services & Hardware

#### MINING_TROUBLESHOOTING.md
**Purpose:** Troubleshooting guide for GPU mining services (lolMiner)
**Contents:** Common issues, diagnostic commands, GPU configuration, systemd integration
**When to Read:** Debugging mining service failures or performance issues
**Location:** `/etc/nixos/docs/MINING_TROUBLESHOOTING.md`

#### storage-configuration.md
**Purpose:** Storage drive inventory, mount status, and known issues
**Contents:** All storage drives across cluster, BTRFS subvolumes, implementation priorities
**When to Read:** Understanding cluster storage layout, troubleshooting mount issues
**Location:** `/etc/nixos/docs/storage-configuration.md`

#### storage-architecture.md (Updated - 2026-03-13)
**Purpose:** Complete cluster storage architecture including K8s integration
**Status:** ✅ Complete
**Contents:**
- All storage technologies (NFS, Garage S3, Syncthing)
- Kubernetes storage classes and tier selection
- Storage design diagrams
- S3 configuration examples
- Backup automation
- Troubleshooting guides
**Location:** `/etc/nixos/docs/storage-architecture.md`

#### STORAGE-CLUSTER-STATUS-REPORT.md
**Purpose:** Current status of cluster storage architecture (NFS, Syncthing, Loki/Promtail)
**Contents:** Service deployment status, mount verification, remaining work, issues found
**When to Read:** Understanding cluster storage state, troubleshooting NFS/Syncthing
**Location:** `/etc/nixos/docs/storage-cluster-status-report.md`

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

## LM Studio Integration

### LM Studio Documentation
**Location:** `/etc/nixos/docs/`

**Purpose:** Complete documentation for LM Studio local LLM deployment

#### Key Documents

##### lmstudio-api-implementation.md
**Purpose:** LM Studio v1 REST API implementation guide
**Status:** ✅ Production Ready
**Contents:**
- Full Pydantic client with async/sync support
- All v1 REST API endpoints
- 256K context window configuration
- MCP integration support
- Multi-GPU allocation strategies

##### lm-studio-headless-setup.md
**Purpose:** Headless/daemon setup with systemd
**Contents:**
- llmster daemon configuration
- NixOS module options
- Multi-GPU setup
- Service management commands
- AI Gateway integration

##### lm-studio-update-guide.md
**Purpose:** Manual update and maintenance procedures
**Contents:**
- Manual installation steps
- NixOS wrapper configuration
- GPU selection options
- Version tracking

##### lm-studio-auto-update.md
**Purpose:** Automated update systemd timer
**Contents:**
- Auto-update service configuration
- Scheduled update intervals
- Rollback procedures

**When to Read:** Setting up or maintaining LM Studio, API integration, multi-GPU configuration

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

## AI Inference Gateway

### Gateway Documentation
**Location:** `/etc/nixos/docs/gateway/`

**Purpose:** Complete documentation for the AI Inference Gateway v2.0.0

#### Key Documents

##### GATEWAY_V2_ALL_TESTS_PASSED.md
**Purpose:** Definitive test report for Gateway v2.0.0
**Status:** ✅ PRODUCTION READY
**Contents:**
- All features tested and verified
- Router specialization matrix
- Performance metrics
- Production readiness checklist

##### gateway-mcp-server-roadmap.md
**Purpose:** MCP server development roadmap
**Status:** Phase 1 Complete, Phase 2 Next
**Contents:** 11-phase implementation plan for gateway management API

##### gateway-feature-roadmap.md
**Purpose:** 2026 feature enhancement roadmap
**Status:** Planning & Prioritization
**Contents:** JSON mode, semantic caching, advanced features

##### gateway-improvement-roadmap.md
**Purpose:** Critical fixes and multi-GPU architecture
**Status:** Draft
**Contents:** Documentation accuracy, health checks, multi-GPU setup

**When to Read:** Working on AI gateway features, MCP integration, or multi-GPU setup

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

### Kubernetes Storage Documentation (NEW - 2026-03-13)
**Location:** `/etc/nixos/docs/kubernetes/storage/`

**Purpose:** Complete storage integration for Kubernetes workloads

#### Key Documents

##### storage-architecture.md (Updated)
**Purpose:** Complete cluster storage architecture including K8s integration
**Status:** ✅ Complete
**Contents:**
- All storage technologies (NFS, Garage S3, Syncthing)
- Kubernetes storage classes and tier selection
- Storage design diagrams
- S3 configuration examples
- Backup automation
- Troubleshooting guides

##### README.md (NEW)
**Purpose:** Kubernetes storage integration guide
**Status:** ✅ Complete
**Contents:**
- Storage architecture overview (decoupled from K8s)
- Quick start guide for applying manifests
- Storage tier selection guide
- Example pod usage
- S3 integration options (API vs CSI)
- Maintenance and troubleshooting

##### storage-classes.yaml (NEW)
**Purpose:** Kubernetes StorageClass definitions
**Status:** ✅ Created, pending application
**Contents:**
- `fast-local-ssd` - Zephyr SSD (databases, ML)
- `nfs-shared-storage` - Nexus NFS (shared data)
- `slow-hdd-storage` - Sentry HDD (logs, archive)
- `garage-s3` - S3 object storage

##### persistent-volumes.yaml (NEW)
**Purpose:** Pre-provisioned PVs mapping to cluster storage
**Status:** ✅ Created, pending application
**Contents:**
- 8 PVs defined for various use cases
- Node affinity for local storage
- NFS mounts for shared storage
- S3 CSI placeholder

##### persistent-volume-claims.yaml (NEW)
**Purpose:** Example PVCs for common use cases
**Status:** ✅ Created
**Contents:**
- PostgreSQL database (fast SSD)
- Shared media files (NFS)
- Application logs (HDD)
- ML model cache (SSD)
- S3 backups (Garage)

##### garage-s3-secret.yaml (NEW)
**Purpose:** S3 credentials for Kubernetes
**Status:** ⚠️ Template (needs agenix integration)
**Contents:**
- S3 endpoint configuration
- Access credentials template
- AWS CLI compatible config
- Environment variable format

##### garage-csi-plan.md (NEW)
**Purpose:** S3 CSI driver integration plan
**Status:** ✅ Complete (Phase 2)
**Contents:**
- CSI driver options comparison
- Implementation steps (Phase 1: Direct API, Phase 2: CSI)
- Testing procedures
- Rollback plan

##### backup-to-garage.nix (NEW)
**Purpose:** NixOS module for automated backups
**Status:** ✅ Created
**Contents:**
- Systemd service and timer
- Configurable backup sources
- Retention policy (30 days default)
- Integration with agenix for secrets

##### backup-to-garage.sh (NEW)
**Purpose:** Backup script (manual or automated)
**Status:** ✅ Complete
**Contents:**
- Backup NixOS config and shared data
- Upload to Garage S3
- Automatic rotation
- List and restore commands

**When to Read:**
- Applying storage manifests to K8s cluster
- Designing storage for new workloads
- Troubleshooting storage issues
- Configuring automated backups
- Kubernetes commands and workflows
- Service migration patterns
- NixOS Kubernetes configuration
- Troubleshooting guide

### Quick Reference

**Current Status:** Phase 1 Complete, Phase 2 In Progress
**Actual State:** Kubernetes v1.35.0 running on 4 nodes
**Target:** Full upstream Kubernetes via `services.kubernetes`
**Timeline:** 9 weeks (estimated)
**Cluster Nodes:** 4 (Zephyr, Nexus, Forge, Sentry) - ALL JOINED ✓

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
1. `just test` - Verify configuration builds
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
5. `just deploy` to apply changes (Colmena handles sync automatically)

---

## Hookify Rules

**Note:** Documentation previously referenced 11 hookify rules at `/data/@projects/.claude/`. That location was incorrect. Actual hooks are configured below:

### JSON Hooks (settings.json)
**Location:** `/etc/nixos/.claude/settings.json`

**PreToolUse Hooks (blocks operations):**
- Prevents editing `hardware-configuration.nix` (auto-generated by nixos-generate-config)
- Prevents editing `flake.lock` (use `nix flake update` instead)

**PostToolUse Hooks:**
- Runs `nix flake check` after editing any `.nix` file

### Markdown Hooks
**Location:** `/etc/nixos/.claude/hookify.require-deployment-success.local.md`

- `require-deployment-success` - Blocks `just deploy`/`just switch` until success is verified

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

**Migration Target:** 31 systemd services identified for Kubernetes migration
**Note:** Additional system services (40+ total) run outside migration scope

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

## Documentation Archive

**Location:** `/etc/nixos/docs/archive/`

**Purpose:** Historical documentation and completed implementation plans

### Archive Structure

```
docs/archive/
├── ARCHIVE_INDEX.md           # Complete archive catalog with reasoning
├── completed-plans/           # Successfully implemented features
├── gateway/                   # Historical gateway testing reports
├── obsolete/                  # Superseded by corrected versions
├── switches/                  # Old switch documentation (incorrect IPs)
└── research/                  # Completed research documents
```

### What's Archived

**Completed Implementation Plans:**
- NUR integration (2026-03-02)
- Spotify SpotX CI/CD (2026-03-02)
- AI Gateway Middleware (2026-03-04)
- Spotify Spicetify (2026-03-03)
- CI/CD Pipeline (2026-03-07)
- Agent Instruction Files (2026-03-08)
- j-kro Agent Federation (2026-03-09)
- Colmena v3 + K8s Integration (2026-03-09)
- Security Hardening (2026-03-09)
- Switch VLAN Design (2026-03-09)
- Vaultwarden + FIDO/Passkeys (2026-03-09)
- Multi-GPU LM Studio Architecture (2026-03-05)

**Gateway Historical Reports:**
- Early test reports (superseded by `docs/gateway/GATEWAY_V2_ALL_TESTS_PASSED.md`)

**Obsolete Documentation:**
- `switch-documentation-summary-OBSOLETE-incorrect-ips.md` (has wrong switch IP mappings)

**Current Information:**
- Use switch docs: `docs/networking/switch-documentation-CORRECTED.md`
- Use gateway status: `docs/gateway/GATEWAY_V2_ALL_TESTS_PASSED.md`

**See:** `docs/archive/ARCHIVE_INDEX.md` for complete archive catalog

---

## Getting Help

### For AI Agents
1. Read relevant documentation sections
2. Check hookify rules for patterns
3. Use `just test` before making changes
4. Follow systematic debugging process (AGENTS.md)

### For Humans
1. **Start here:** STATUS.md for real-time cluster state
2. Then: Review DOCUMENTATION_INDEX.md for full documentation catalog
3. Check ROADMAP.md for migration plan and progress
4. Use `just status` for quick cluster health check
5. Review logs: `journalctl -xe` for errors

### Common Tasks

**Deploy configuration:**
```bash
just test && just deploy
```

**Note:** Manual `just sync` is no longer required - Colmena handles configuration distribution automatically.

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

### 2026-03-14
- **BUILD FIXES:** Fixed multiple NixOS build issues on x86-64-v3-migration branch
  - Fixed Python encodings module error (nix-store --repair-path)
  - Fixed wrong substituter URL (consolidated in distributed-builds.nix with lib.mkForce)
  - Fixed duplicate cache.nixos.org entries
  - Fixed corrupted yakuake source
  - Fixed NFS automount mkdir failure (removed for automount paths)
  - Fixed CNI directory warning (changed tmpfiles directive to 'C')
  - Fixed agenix boot error (removed corrupted tplink-password.age)
- **DOCUMENTATION:** Fixed Hookify Rules documentation drift (removed incorrect /data/@projects/.claude/ reference)

### 2026-03-13
- **DOCUMENTATION AUDIT:** Fixed critical documentation drift
- Updated ROADMAP.md status from "Planning Phase" to "Phase 1 Complete"
- Fixed broken research doc paths (moved to archive/research/)
- Updated cluster version to reflect actual K8s state
- Verified monitoring stack is operational (not deferred)
- Created STATUS.md for real-time cluster state tracking

### 2026-03-13
- Created STORAGE-CLUSTER-STATUS-REPORT.md (verified deployment status: 87% complete)
- Updated cluster-storage-implementation.md with actual completion status
- Updated cluster-storage-design.md with verified progress
- Found that NFS, Syncthing, Loki/Promtail were already deployed and operational
- Identified Garage as remaining task (module imported but not enabled)
- Found issue: Forge mounts /etc/nixos as read-write (should be read-only)

### 2026-03-09
- Created MINING_TROUBLESHOOTING.md (comprehensive lolMiner debugging guide)
- Fixed lolMiner OpenCL ICD path bug (tmpfiles symlink workaround)
- Fixed lolMiner OpenCL detection (added OCL_ICD_VENDORS environment variable)
- Both mining services operational (17 g/s combined on Forge)

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
**Cluster Version:** Phase 1 Complete (K8s v1.35.0 running)
**Next Review:** After Phase 2 completion (Week 3)
