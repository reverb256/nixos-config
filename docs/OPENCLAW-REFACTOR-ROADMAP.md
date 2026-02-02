# OpenClaw Implementation - Situation Report & Roadmap

**Generated:** 2026-02-02  
**Branch:** feature/openclaw-secure  
**Status:** Refactoring in progress

---

## Executive Summary

Current OpenClaw implementation has a **critical issue** with duplicate, conflicting configurations between NixOS modules and Home Manager modules. This causes the hasown dependency workaround to be applied at the system level but ignored because Home Manager provides its own binary.

### Key Findings

| Issue | Severity | Impact |
|-------|----------|--------|
| Duplicate OpenClaw configs (NixOS + HM) | 🔴 Critical | Binary mismatch, workaround ignored |
| Package reference conflicts | 🔴 High | System overlay not applied to HM |
| Unclear service ownership | 🟡 Medium | Both systemd.user and systemd.service may try to start |
| Documentation outdated | 🟡 Medium | Doesn't reflect current architecture |

---

## Current Architecture Problem

```
Current State (BROKEN):
┌─────────────────────────────────────────────────────────────────┐
│ ZEPHYR                                                           │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ NixOS Module (modules/openclaw.nix)                        │  │
│  │ - Creates systemd.service: openclaw                        │  │
│  │ - Uses pkgs.openclaw-gateway (with workaround overlay)     │  │
│  │ - Runs as 'lobster' user, systemd hardening enabled        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Home Manager (home.nix → nix-openclaw.homeManagerModules) │  │
│  │ - Creates programs.openclaw enable                        │  │
│  │ - Provides /etc/profiles path binary (OLD, no workaround) │  │
│  │ - User-level CLI access only                              │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  USER sees: /etc/profiles/per-user/j_kro/bin/openclaw → OLD PKG │
│  SYSTEM sees: /nix/store/r45l6kiv.../bin/openclaw → NEW PKG    │
└─────────────────────────────────────────────────────────────────┘
```

### Root Cause Analysis

1. **Home Manager shadows system package**: The `openclaw` command in PATH points to Home Manager's profile, not the system profile
2. **Two package sources**: NixOS module uses overlayed `pkgs.openclaw-gateway`, HM module uses direct input reference
3. **Service duplication risk**: Both may try to manage the same service
4. **hasown workaround applied but not used**: System package has the fix, but user runs the old HM package

---

## Intended Architecture (Upstream Pattern)

Based on research of nix-openclaw repository, the intended design is:

```
Intended State (CORRECT):
┌─────────────────────────────────────────────────────────────────┐
│ ZEPHYR                                                           │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ NixOS Module (modules/openclaw.nix)                        │  │
│  │ - System-level service management (systemd.service)        │  │
│  │ - Runs as 'lobster' user                                   │  │
│  │ - Health monitoring, firewall rules                        │  │
│  │ - Environment file management via agenix                   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Home Manager (home.nix → programs.openclaw)                │  │
│  │ - User-level configuration only                            │  │
│  │ - No service management (delegated to NixOS)               │  │
│  │ - CLI tool access via hm profile                           │  │
│  │ - Instance configuration (if needed)                       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  USER CLI: /etc/profiles/per-user/j_kro/bin/openclaw → NEW PKG  │
│  SERVICE: systemd.service openclaw → NEW PKG (same binary)      │
└─────────────────────────────────────────────────────────────────┘
```

### Key Principles

1. **Service at system level only**: OpenClaw runs as a systemd service (system-wide)
2. **Home Manager for user access**: HM provides the CLI binary and user configuration
3. **Single package source**: Both service and CLI use the same overlayed package
4. **Clear separation**: System handles service, HM handles user preferences

---

## Roadmap

### Phase 1: Current Cleanup (In Progress)

- [x] **Commit 7b26da5**: Add hasown workaround overlay
- [ ] **TBD**: Remove duplicate NixOS module (keep only one authoritative source)
- [ ] **TBD**: Harmonize package references to use single source

### Phase 2: Architecture Refactor

- [ ] **Step 1**: Remove conflicting NixOS module or make it delegate to HM
- [ ] **Step 2**: Ensure HM module uses the same package as the workaround overlay
- [ ] **Step 3**: Remove systemd service from NixOS module (HM handles it)
- [ ] **Step 4**: Keep only system-level concerns in NixOS:
  - User/group creation (lobster)
  - Firewall rules
  - Environment file via agenix
  - Health monitoring

### Phase 3: Verification & Testing

- [ ] **Test 1**: `openclaw gateway` runs without hasown error
- [ ] **Test 2**: `systemctl status openclaw` shows service running
- [ ] **Test 3**: Health checks pass
- [ ] **Test 4**: Both CLI and service use same binary

### Phase 4: Documentation Update

- [ ] Update AGENTS.md with new architecture
- [ ] Update OPENCLAW-SUMMARY.md
- [ ] Update AISTOR-DEPLOY.md
- [ ] Create architecture diagram

---

## Files to Modify

| File | Change |
|------|--------|
| `modules/openclaw.nix` | Simplify to system-level only, delegate service to HM |
| `modules/openclaw-common.nix` | Ensure only system-level concerns |
| `home.nix` | Remove/keep HM module appropriately |
| `hosts/zephyr/configuration.nix` | May need adjustment |
| Documentation files | Update after refactor |

## Files to Create (if needed)

| File | Purpose |
|------|---------|
| `docs/OPENCLAW-REFACTOR.md` | Detailed refactor notes |
| `docs/ARCHITECTURE.md` | System architecture diagrams |

---

## Immediate Actions

### Option A: Full Refactor (Recommended)
Follow upstream pattern:
1. Remove NixOS service module, keep only system-level concerns
2. Let Home Manager handle the actual service
3. Ensure both use same package (with workaround)

### Option B: Quick Fix (Temporary)
Keep current structure but:
1. Remove HM openclaw module
2. Use system-level package only
3. Simpler, but diverges from upstream pattern

**Recommendation**: Option A (follow upstream pattern for long-term maintainability)

---

## Next Steps

1. Wait for librarian research to complete (understanding HM module)
2. Decide on refactor approach (A or B)
3. Execute Phase 2 refactor
4. Test and verify
5. Update documentation
6. Commit changes

---

## Open Questions

1. Should we keep the hasown workaround as a permanent fix or wait for upstream to resolve issue #45?
2. Do we need the nginx reverse proxy, or can we use OpenClaw directly with auth?
3. Is the storage MCP (openclaw-storage.nix) still needed, or should it be merged?

---

*Last updated: 2026-02-02*
