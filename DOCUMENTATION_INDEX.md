# NixOS Cluster Documentation Index

**Last Updated:** 2026-03-19 | **Cluster Version:** Phase 2 Complete, HA Control Plane (K8s v1.35.0) | **Agent Files:** Template-based v1.0

Complete index of all documentation for the NixOS cluster, including the ongoing Kubernetes migration.

---

## Quick Start

**For AI Agents:**
1. Read `/etc/nixos/AGENTS.md` for universal cluster patterns
2. Read agent-specific file: `CLAUDE.md`, `.github/copilot-instructions.md`, `.cursorrules`, or `QWEN.md`
3. Check `/etc/nixos/ROADMAP.md` for current migration status

**For Humans:**
1. **First:** `STATUS.md` for real-time cluster state
2. Read this index for full documentation catalog
3. Use `just` commands for all operations

---

## Core Documentation

| Document | Purpose | Location |
|----------|---------|----------|
| **DECISION_LOG.md** | Architectural decisions & rationale (19 decisions) | `docs/DECISION_LOG.md` |
| **STATUS.md** | Real-time cluster health & migration progress | `STATUS.md` |
| **AGENTS.md** | Universal guidelines for ALL AI agents | `AGENTS.md` |
| **CLAUDE.md** | Claude Code-specific patterns | `CLAUDE.md` |
| **ROADMAP.md** | Kubernetes migration plan (9-week timeline) | `ROADMAP.md` |
| **Copilot Instructions** | GitHub Copilot guidelines | `.github/copilot-instructions.md` |
| **Cursor Rules** | Cursor IDE guidelines | `.cursorrules` |
| **QWEN.md** | Qwen-Agent patterns | `QWEN.md` |

### Agenix Secrets Management
- **Location:** `skills/agenix-secrets/`
- **Key Docs:** SKILL.md, README.md, HOST_KEY_SETUP_GUIDE.md
- **Module:** `modules/system/agenix-secrets-registry.nix`
- **Guide:** `docs/agenix-multi-host-deployment.md`
- **Quick Add Secret:**
  ```bash
  echo "value" | agenix -e secrets/name.age
  # Add both "name.age" and "secrets/name.age" to secrets.nix
  sudo nixos-rebuild switch --flake .#zephyr
  ```

---

## Operational Documentation

### Marketplace & Compute
- **compute-market.md** - GPU Resource Marketplace (architecture, config, metrics)
- **compute-market-testing.md** - Testing guide & verification procedures

### Deployment Guides
- **DEPLOYMENT_COMPLETE.md** - Cluster deployment summary
- **switch-configuration-guide.md** - NixOS configuration switches

### Services & Hardware
- **MINING_TROUBLESHOOTING.md** - lolMiner GPU mining issues
- **akash-cloudflare-integration.md** - 6 automation features (DNS, cache, metrics, health, cleanup, status)
- **akash-cloudflare-integration-summary.md** - Implementation summary
- **CUDA_TROUBLESHOOTING.md** - CUDA setup, multi-GPU, troubleshooting
- **storage-configuration.md** - Storage drive inventory & mount status
  - **Note:** For K8s storage, see `docs/kubernetes/storage/storage-architecture.md`
  - **Archived:** Old 3-way replication docs moved to `docs/archive/obsolete/storage/`

### Monitoring & Testing
- **COMPREHENSIVE_TEST_REPORT.md** - Full cluster testing results
- **TEST_REPORT.md** - Standard test results

---

## Architecture & Design

| Document | Purpose | Location |
|----------|---------|----------|
| **network-analysis-report.md** | Network config (Tailscale, Unbound, gateway) | `network-analysis-report.md` |
| **RAG_DESIGN.md** | RAG system architecture | `RAG_DESIGN.md` |
| **RAG_TEST_REPORT.md** | RAG testing results | `RAG_TEST_REPORT.md` |

---

## LM Studio Integration

**Location:** `docs/`

- **lmstudio-api-implementation.md** - v1 REST API, Pydantic client, 256K context
- **lm-studio-headless-setup.md** - llmster daemon, systemd, multi-GPU
- **lm-studio-update-guide.md** - Manual update procedures
- **lm-studio-auto-update.md** - Automated update timer

---

## Integration & Skills

### MCP Integration
- **SKILL_MCP_INTEGRATION_COMPLETE.md** - MCP server setup & testing
- **INTEGRATION_SUMMARY.md** - Overall integration status

### Skill Consolidation
- **SKILL-CONSOLIDATION-PLAN.md** - Consolidation strategy
- **SKILL-CONSOLIDATION-IMPLEMENTATION.md** - Technical implementation
- **SKILL-CONSOLIDATION-SUMMARY.md** - Results & benefits

---

## Special Projects

- **INSIGHTS.md** - Lessons learned & optimization opportunities
- **SPACEBOT_IMPLEMENTATION.md** - Spacebot project details

---

## AI Inference Gateway

**Location:** `docs/gateway/`

- **GATEWAY_V2_ALL_TESTS_PASSED.md** - v2.0.0 test report (✅ Production Ready)
- **gateway-mcp-server-roadmap.md** - 11-phase MCP API plan (Phase 1 complete)
- **gateway-feature-roadmap.md** - 2026 enhancements (JSON mode, caching)
- **gateway-improvement-roadmap.md** - Critical fixes & multi-GPU

---

## Kubernetes Migration

### Primary Docs
- **ROADMAP.md** (685 lines) - Complete 9-week migration plan, 7 phases, GPU strategy
- **AGENTS.md** - K8s commands, workflows, NixOS configuration, troubleshooting

### Control Plane
- **control-plane-architecture.md** - 3-node HA (Zephyr, Nexus, Sentry), Keepalived VIP, etcd cluster
  - **Note:** Old HA docs (HAProxy) archived to `docs/archive/obsolete/kubernetes/`

### Storage
**Location:** `docs/kubernetes/storage/`

- **storage-architecture.md** - Storage classes (beta2, beta3, ram, garage-s3), capacity, Garage S3
- **README.md** - Integration guide, quick start, tier selection
- **storage-classes.yaml** - K8s StorageClass definitions
- **persistent-volumes.yaml** - Pre-provisioned PVs (8 PVs, node affinity)
- **persistent-volume-claims.yaml** - Example PVCs (PostgreSQL, media, logs, ML, S3)
- **garage-s3-secret.yaml** - S3 credentials template (⚠️ needs agenix)
- **garage-csi-plan.md** - S3 CSI driver integration (Phase 2 complete)
- **backup-to-garage.nix** - Automated backup module
- **backup-to-garage.sh** - Backup script with rotation

### Ingress
- **caddy-ingress.md** - Caddy Ingress Controller (DaemonSet, Prometheus metrics)
  - **Manifests:** `kubernetes-manifests/ingress/`
  - **Features:** Auto HTTPS, HTTP/3, NodePort 30080/30443

### Quick Reference
- **Status:** Phase 1 Complete, Phase 2 In Progress
- **K8s Version:** v1.35.0 on 4 nodes (Zephyr, Nexus, Forge, Sentry)
- **Timeline:** 9 weeks
- **Decisions:** Full K8s (not K3s), Flannel CNI, Longhorn storage, NixOS module

---

## Workflow Documentation

### Justfile Commands
```bash
# Primary
just test              # Verify configuration
just switch            # Apply to local host
just deploy            # Deploy to all hosts
just status            # Show cluster status

# Host-specific
just zephyr|nexus|forge|sentry  # Deploy to specific host

# CI/CD
just ci-local          # Run CI locally
just health-check      # Cluster health check
just rollback          # Rollback to previous generation
```

### Critical Workflows
- **Before Deployment:** `just test` → check storage → review hookify warnings
- **Storage Verify:** `/data/@projects/infra/nixos/verify-cluster-storage.sh`
- **Git Workflow:** Make changes → `git add` new files → `git commit` → `just test` → `just deploy`

---

## Hookify Rules

**Location:** `.claude/settings.json` and `.claude/hookify.require-deployment-success.local.md`

**JSON Hooks:**
- **PreToolUse:** Block editing `hardware-configuration.nix`, `flake.lock`
- **PostToolUse:** Run `nix flake check` after editing `.nix` files

**Markdown Hooks:**
- `require-deployment-success` - Block `just deploy`/`just switch` until verified

---

## Cluster Inventory

### Hosts

| Host | CPU | RAM | GPUs | Storage | Roles |
|------|-----|-----|------|---------|-------|
| **Zephyr** | AMD 5950X (32 cores) | 31GB | RTX 3090 + 3060 Ti | 1.85TB SSD | Control plane, workstation, gaming, VR, mining, AI |
| **Nexus** | AMD Zen (24 cores) | 46GB | 1x RTX 3060 Ti | 4.7TB | Storage, gaming, mining, AI |
| **Forge** | Intel Skylake (6 cores) | 15GB | 2x RTX 4060 + 2x RX 5700 XT | 446GB SSD | Multi-GPU mining, AI |
| **Sentry** | AMD Zen (16 cores) | 31GB | RX 5600 XT | 1.23TB | Mining, monitoring |

**Total Resources:** 78 cores, 123GB RAM, 7 GPUs (5× NVIDIA + 2× AMD), 8.4TB storage

### Services
- **Migration Target:** 31 systemd services to K8s (40+ additional system services)
- **Categories:** AI/ML (5), Databases (2), Dev Tools (3), File Sync (1), Gaming (4), Media (3), Monitoring (3), Networking (3), Productivity (2), Web (5)

---

## Documentation Maintenance

**Update Immediately:** Adding services, changing workflows, updating hardware, discovering patterns, completing phases

**Review Weekly:** ROADMAP.md, AGENTS.md, Hookify rules

**Standards:** Markdown format, clear tone, AI/human audience, git-tracked

**Quality:** Clear purpose, accurate details, actionable instructions, examples, cross-references, date stamp

---

## Documentation Archive

**Location:** `docs/archive/`

**Structure:** `ARCHIVE_INDEX.md`, `completed-plans/`, `gateway/`, `obsolete/`, `switches/`, `research/`

**Archived Content:**
- Completed implementation plans (NUR, Spotify, Gateway, CI/CD, etc.)
- Gateway historical reports
- Obsolete docs (switch IPs, storage 3-way claims, HAProxy references)
- Research documents

**See:** `docs/archive/ARCHIVE_INDEX.md` for complete catalog

---

## Getting Help

### For AI Agents
1. Read relevant documentation
2. Check hookify rules
3. Use `just test` before changes
4. Follow systematic debugging (AGENTS.md)

### For Humans
1. **Start:** STATUS.md for real-time state
2. **Then:** DOCUMENTATION_INDEX.md for catalog
3. **Check:** ROADMAP.md for migration plan
4. **Quick:** `just status` for health check
5. **Logs:** `journalctl -xe` for errors

### Common Tasks
```bash
# Deploy
just test && just deploy

# Health
just status
just health-check

# Logs
journalctl -u <service> -f
systemctl status <service>

# K8s debug
kubectl get nodes
kubectl get pods --all-namespaces
kubectl logs <pod> -n <namespace>
```

---

## Agent Instruction Files

### Template System (v1.0)
- **MAINTENANCE.md** - Guide for maintaining agent files
- **2026-03-08-agent-instruction-files-spec-design.md** - Complete design specification

### Agent Files
- **AGENTS.md** - Universal patterns (327 lines, target: 500)
- **CLAUDE.md** - Claude Code specific (106 lines, target: 200)
- **QWEN.md** - Qwen-Agent specific (98 lines, target: 200)

---

## Recent Changes (Summary)

**2026-03-19:** Cloudflare integration for Akash (6 automation features, ~200 hrs/year savings)

**2026-03-16:** Documentation audit & cleanup, archived incorrect storage/HA docs, created DECISION_LOG.md

**2026-03-15:** AI Gateway quick wins (tool loop detection, streaming tools, Files API with Garage S3)

**2026-03-14:** Caddy Ingress deployed, network constants added, build fixes

**2026-03-13:** Documentation audit fixed drift, STATUS.md created

**2026-03-09:** MINING_TROUBLESHOOTING.md created, lolMiner fixes

**2026-03-08:** DOCUMENTATION_INDEX.md created, ROADMAP.md (685 lines), 11 hookify rules

---

**Document Owner:** j_kro
**Version:** 3.0 | **Updated:** 2026-03-22
**Changes:** Reduced from 1157 to 375 lines (-68%), removed duplicates, compressed verbose sections, summarized changelog
