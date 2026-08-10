# NixOS Cluster Documentation Index

**Status:** Canonical catalog
**Owner:** j_kro
**Last Verified:** 2026-08-09
**Scope:** Repository documentation navigation; not a live cluster-health report
**Current-state reference:** [`docs/current-state.md`](docs/current-state.md)
**Most recent broad audit indexed:** [`docs/audit-2026-07-27.md`](docs/audit-2026-07-27.md)

Complete index of the NixOS cluster documentation. Migration plans and dated audits are
historical/planning context unless explicitly re-verified. Use `docs/current-state.md`
for the authority boundaries and `just health`/`just provenance` for live claims.

---

## Quick Start

**For AI Agents:**
1. Read `/etc/nixos/AGENTS.md` for universal cluster patterns
2. Read agent-specific file: `CLAUDE.md`, `.github/copilot-instructions.md`, `.cursorrules`, or `QWEN.md`
3. Read [`docs/current-state.md`](docs/current-state.md) for checked-in architecture and authority boundaries
4. Treat `ROADMAP.md` and dated audits as planning/history; verify their claims against source and live state before acting.

**For Humans:**
1. Read [`docs/current-state.md`](docs/current-state.md) for authority boundaries
2. Run `just health`, `just status`, or `just provenance` for live state
3. Read this index for the documentation catalog
4. Use `just` commands for operations; do not follow historical commands blindly

---

## Core Documentation

| Document | Purpose | Location |
|----------|---------|----------|
| **Decision record index** | Architectural decisions, rationale, and source links | [`docs/DECISION_LOG.md`](docs/DECISION_LOG.md) |
| **Decision table** | Current open/completed decisions and rationale | [`ACTION-ITEMS.md`](ACTION-ITEMS.md#decision-log) |
| **Current state** | Checked-in architecture and documentation authority boundaries | `docs/current-state.md` |
| **STATUS.md** | Generated status snapshot; verify its timestamp before relying on it | `STATUS.md` |
| **AGENTS.md** | Universal guidelines for ALL AI agents | `AGENTS.md` |
| **CLAUDE.md** | Claude Code-specific patterns | `CLAUDE.md` |
| **CONTRIBUTING.md** | Worktree, PR, and contribution workflow | `CONTRIBUTING.md` |
| **DOCS-MAINTENANCE.md** | Documentation classification and freshness policy | `DOCS-MAINTENANCE.md` |
| **ROADMAP.md** | Historical Kubernetes migration roadmap and hardening notes | `ROADMAP.md` |
| **Copilot Instructions** | GitHub Copilot guidelines | `.github/copilot-instructions.md` |
| **Cursor Rules** | Cursor IDE guidelines | `.cursorrules` |
| **QWEN.md** | Qwen-Agent patterns | `QWEN.md` |

### Secrets Management
- **Current boundary:** SecretSpec is the runtime resolution path; sops-nix remains a
  compatibility path during the migration. See [`docs/current-state.md`](docs/current-state.md)
  and [`SOPS-NIX.md`](SOPS-NIX.md) before changing secret wiring.
- **Declarations:** `secretspec.toml` and the host SecretSpec wiring under `hosts/`
- **Encrypted material:** `secrets/` (do not place plaintext values in documentation)
- **Legacy references:** historical Agenix plans and dead-module references are retained
  only as archive/audit evidence; do not use them as current procedures.

---

## Decision records

Use [`docs/DECISION_LOG.md`](docs/DECISION_LOG.md) as the canonical decision-record index.
The detailed current decision table remains in [`ACTION-ITEMS.md`](ACTION-ITEMS.md#decision-log);
dated audits and archived reports remain historical evidence.

## Operational Documentation

### Marketplace & Compute
- **compute-market.md** - GPU Resource Marketplace (architecture, config, metrics)
- **compute-market-testing.md** - Testing guide & verification procedures

### Deployment Guides
- **DEPLOYMENT_COMPLETE.md** - Cluster deployment summary
- **switch-configuration-guide.md** - NixOS configuration switches

### Services & Hardware
- **MINING_TROUBLESHOOTING.md** - lolMiner GPU mining issues
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

> The details in this section are navigation and checked-in reference pointers, not a live
> cluster report. Verify versions, routes, node placement, and service status against
> `kubernetes/`, `kubernetes-manifests/`, `contracts/host-inventory.nix`, and live
> Kubernetes queries before acting.

### Primary Docs
- **ROADMAP.md** - Historical migration plan and current K3s hardening notes
- **AGENTS.md** - K8s commands, workflows, NixOS configuration, troubleshooting

### Control Plane
- **control-plane-architecture.md** - 3-node HA (Zephyr, Nexus, Sentry), Keepalived VIP, etcd cluster
  - **Note:** Old HA docs (HAProxy) archived to `docs/archive/obsolete/kubernetes/`

### Storage
**Location:** `docs/kubernetes/storage/`

- **storage-architecture.md** - Storage classes and architecture reference; verify against
  the current Nix/Easykubenix modules before making capacity or provisioner claims.
- **README.md** - Local storage documentation navigation
- **storage-classes.yaml**, **persistent-volumes.yaml**, **persistent-volume-claims.yaml** -
  Reference definitions; determine whether each is generated, bootstrap-only, or active
  before applying it.
- **garage-csi-plan.md** - Historical/planning reference unless re-verified
- **backup-to-garage.nix**, **backup-to-garage.sh** - Backup implementation references;
  inspect source and deployment ownership before running

### Ingress
- **caddy-ingress-architecture.md** - Ingress architecture reference; verify VIP, TLS,
  DNS, NodePorts, and backends against current Nix/Caddy/Kubernetes sources.
- **caddy-ingress.md** - Caddy ingress controller reference
  - **Manifest area:** `kubernetes-manifests/ingress/`

### Quick Reference
- **Status:** K3s configuration is checked in; consult `docs/current-state.md` and run live health commands before making runtime claims
- **Kubernetes:** K3s configuration and version declarations live in the checked-in Nix modules;
  verify the exact deployed version before making runtime claims.
- **Topology:** 4 configured hosts — Zephyr, Nexus, Forge, and Sentry
- **CNI:** Check the current K3s/Nix configuration and live node state before relying on this detail.
- **Decisions:** K3s via the checked-in NixOS configuration; use `docs/current-state.md` for
  authority boundaries and `ROADMAP.md` only as migration/history context.

---

## Workflow Documentation

### Justfile Commands
```bash
# Primary
just check             # Fast flake validation
just build             # Build current host (offloads from Zephyr)
just test-apply        # Test activation without a permanent switch
just switch            # Apply to local host
just deploy            # Deploy to all hosts
just status             # Show cluster status

# Host-specific
just zephyr              # Deploy to zephyr
just nexus               # Deploy to nexus
just forge               # Deploy to forge
just sentry              # Deploy to sentry

# CI/CD
just check             # Fast flake validation
just build             # Build current host
just health            # Cluster health check
just rollback          # Rollback to previous generation
```

### Critical Workflows
- **Before Deployment:** `just check` → targeted build/test → preflight → review hookify warnings
- **Storage Verify:** `/data/@projects/infra/nixos/verify-cluster-storage.sh`
- **Git Workflow:** Make changes → `git add` new files → `git commit` → `just check`/targeted build → `just deploy`

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

> These are checked-in planning/inventory values, not live hardware evidence. The typed
> source is [`contracts/host-inventory.nix`](contracts/host-inventory.nix); verify current
> hardware and deployed roles before operational decisions.

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

## Supply Chain Security

### Package Manager Cooldowns (7-day age gate)
- **Module:** `modules/services/supply-chain-cooldowns.nix` — Writes cooldown configs to user home
- **npm:** `min-release-age=7` in `~/.npmrc`
- **bun:** `minimumReleaseAge = "7d"` in `~/.bunfig.toml`
- **uv (Python):** `exclude-newer = "7 days"` in `~/.config/uv/uv.toml`

### Container Image Security
- **Image policy:** `modules/services/podman.nix` — Rejects unknown registries, allows docker.io/library, ghcr.io, quay.io, localhost
- **Image pinning:** The repository has admission and policy controls against mutable image tags;
  verify each workload source before asserting that every image is pinned:
  - `vaultwarden/server:1.35.4`, `glitchtip/glitchtip:6`, `postgres:16-alpine`, `redis:7-alpine`
- **Container scanning:** `modules/services/container-scanning.nix` — Trivy weekly scan (HIGH/CRITICAL CVEs)
- **Auto-update age check:** `modules/services/podman-auto-update.nix` — Warns on images < 7 days old

### Kubernetes Admission Policy
- **File:** `kubernetes-manifests/security/deny-latest-tag.yaml`
- **Type:** `ValidatingAdmissionPolicy` — Blocks `:latest` tags on all pods/deployments/daemonsets/statefulsets

### CI/CD Security
- **GitHub Actions:** All workflows (`.github/workflows/`) pin actions to immutable commit SHAs
- **Flake input age:** `modules/services/auto-update.nix` validates nixpkgs input > 7 days before auto-updating

---

## Documentation Maintenance

**Update Immediately:** Adding services, changing workflows, updating hardware, discovering patterns, completing phases

**Review Weekly:** ROADMAP.md, AGENTS.md, Hookify rules

**Standards:** Markdown format, clear tone, AI/human audience, git-tracked

**Quality:** Clear purpose, accurate details, actionable instructions, examples, cross-references, date stamp

---

## Documentation Archive

**Location:** `docs/archive/`

**Structure:** `ARCHIVE_INDEX.md`, `obsolete/`, and `legacy/`.

**Archived Content:**
- Completed implementation plans and historical reports
- Superseded or incorrect operational references
- Preserved former uppercase archive tree under `docs/archive/legacy/ARCHIVE/`
- Preserved former LIVE snapshots under `docs/archive/legacy/live-snapshots/`

**See:** `docs/archive/ARCHIVE_INDEX.md` for the canonical catalog.
Do not treat archive contents as current procedures.

---

## Getting Help

### For AI Agents
1. Read relevant documentation
2. Check hookify rules
3. Use `just check` and targeted build validation before changes
4. Follow systematic debugging (AGENTS.md)

### For Humans
1. **Start:** `docs/current-state.md` for authority boundaries
2. **Then:** `DOCUMENTATION_INDEX.md` for catalog
3. **Check:** `just status`, `just health`, and `just provenance` for runtime state
4. **Use:** `ROADMAP.md` for migration history and remaining hardening context
5. **Logs:** `journalctl -xe` for errors

### Common Tasks
```bash
# Deploy
just check && just deploy

# Health
just status
just health

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

**2026-07-27:** Multi-area audit completed — [`docs/audit-2026-07-27.md`](docs/audit-2026-07-27.md). 24 findings (F-1..F-24) across secrets, config, K8s, docs. Auto-fixed `.gitignore` (.env), `secretspec.toml` (route_count 24→51), `overlay.nix` (dead block), `hosts/zephyr/secretspec-creds-wiring.nix` (ZAI_API_KEY), 3 stale-doc warnings (F-21, F-22). HIGH-severity findings F-1/F-2/F-3/F-5/F-6 queued for operator action.

**2026-07-25:** SECURITY-INCIDENT-2026-07-25.md — secretspec Phase 2 complete + SAMSUNG_TV_TOKEN routing regression discovered.

**2026-07-15:** Z.AI/GLM provider fully removed cluster-wide (referenced `ZAI_API_KEY`). Freedom model removed from Hermes profile.

**2026-05-23:** Phase 5 (GPU Workloads) deliverables final — llama.cpp + AI Gateway integration verified (24.7 tok/s on 3090).

**2026-05-14:** Caddy forward_auth wired (`central-auth`), K8s oauth2-proxy sidecars removed (centralized SSO). Sovereign Service Mesh Phase 1 operational.

**2026-04-07:** K3s migration audit completed — CNI deployment (Flannel VXLAN), iptables/kube-proxy fixes, 5 NVIDIA GPUs registered (forge=2, nexus=1, zephyr=2).

**2026-03-19:** Cloudflare integration automation (6 features, ~200 hrs/year savings)

**2026-03-16:** Documentation audit & cleanup, archived incorrect storage/HA docs, created DECISION_LOG.md

**2026-03-15:** AI Gateway quick wins (tool loop detection, streaming tools, Files API with Garage S3)

**2026-03-14:** Caddy Ingress deployed, network constants added, build fixes

**2026-03-13:** Documentation audit fixed drift, STATUS.md created

**2026-03-09:** MINING_TROUBLESHOOTING.md created, lolMiner fixes

**2026-03-08:** DOCUMENTATION_INDEX.md created, ROADMAP.md (685 lines), 11 hookify rules

---

**Document Owner:** j_kro
**Status:** Canonical catalog
**Last Verified:** 2026-08-09
**Changes (2026-08-09):** Added the checked-in current-state authority boundary and removed obsolete current-state/Secret management guidance from the navigation spine.
