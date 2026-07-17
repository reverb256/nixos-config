# Documentation Archive Index

**Created:** 2026-03-11
**Purpose:** Track all archived documentation with reasoning and current locations

---

## Archive Structure

```
docs/archive/
├── ARCHIVE_INDEX.md           # This file
├── completed-plans/           # Successfully implemented design/implementation pairs
├── gateway/                   # Historical gateway testing reports
├── obsolete/                  # Documents superseded by corrected versions
└── switches/                  # Switch documentation (incorrect IP mappings)
```

---

## Completed Implementation Plans

### NUR Integration (2026-03-02)
**Status:** ✅ Complete
**Reason:** NUR (Nix User Repository) integration successfully implemented

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-02-nur-integration-design.md` | Design specification | See implementation |
| `2026-03-02-nur-integration.md` | Implementation details | `docs/nur-usage.md` |

---

### Spotify SpotX CI/CD (2026-03-02)
**Status:** ✅ Complete
**Reason:** Spotify SpotX CI/CD pipeline implemented

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-02-spotify-spotx-cicd-design.md` | Design specification | See implementation |
| `2026-03-02-spotify-spotx-cicd.md` | Implementation details | `docs/spotify-spotx-usage.md` |

---

### AI Gateway Middleware (2026-03-04)
**Status:** ✅ Complete - Gateway v2.0.0 Production Ready
**Reason:** Router integration, OpenAI SDK migration, all features tested

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-04-ai-gateway-middleware-design.md` | Design specification | See implementation |
| `2026-03-04-ai-gateway-middleware-implementation.md` | Implementation details | `docs/GATEWAY_V2_ALL_TESTS_PASSED.md` |

---

### Spotify Spicetify (2026-03-03)
**Status:** ✅ Complete
**Reason:** Spicetify integration implemented

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-03-spotify-spicetify-design.md` | Design specification | `docs/spotify-spicetify-usage.md` |

---

### CI/CD Pipeline (2026-03-07)
**Status:** ✅ Complete
**Reason:** CI/CD pipeline with distributed builds implemented

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-07-ci-cd-pipeline-design.md` | Design specification | See implementation |
| `2026-03-07-ci-cd-pipeline.md` | Implementation details | `.github/` workflows |

---

### Agent Instruction Files (2026-03-08)
**Status:** ✅ Complete
**Reason:** Template-based agent instruction file system implemented

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-08-agent-instruction-files-spec-design.md` | Design specification | `docs/templates/` system |

---

### j-kro Agent Federation (2026-03-09)
**Status:** ✅ Complete
**Reason:** 7-agent Spacebot federation deployed

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-09-j-kro-agent-federation-design.md` | Design specification | See implementation |
| `2026-03-09-j-kro-agent-federation-implementation.md` | Implementation details | `docs/SPACEBOT_SETUP_GUIDE.md` |

---

### Colmena v3 + K8s Integration (2026-03-09)
**Status:** ✅ Complete - Phase 0 Foundation
**Reason:** Colmena deployment with x86-64-v3 optimization, distributed builds

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-09-colmena-v3-k8s-integration-design.md` | Design specification | See implementation |
| `2026-03-09-colmena-v3-implementation-plan.md` | Implementation details | `machines.nix`, flake.nix |

---

### Security Hardening (2026-03-09)
**Status:** ✅ Complete
**Reason:** Security audit recommendations implemented

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-09-security-hardening-implementation.md` | Implementation details | `docs/security/SECURITY_AUDIT_REPORT.md` |

---

### Switch VLAN Design (2026-03-09)
**Status:** ✅ Implementation Ready
**Reason:** 7-VLAN segmentation design for TP-Link switches

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-09-switch-vlan-design.md` | Design specification | `docs/networking/` VLAN docs |

---

### Vaultwarden + FIDO/Passkeys (2026-03-09)
**Status:** ✅ Complete
**Reason:** Vaultwarden deployed with FIDO2 WebAuthn support

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-09-vaultwarden-fido-passkeys-design.md` | Design specification | See implementation |
| `2026-03-09-vaultwarden-fido-passkeys-implementation.md` | Implementation details | `modules/services/vaultwarden.nix` |

---

### Multi-GPU LM Studio Architecture (2026-03-05)
**Status:** 📋 Design Document
**Reason:** Multi-machine multi-GPU LM Studio architecture for Spacebot

| File | Purpose | Current Info Location |
|------|---------|----------------------|
| `2026-03-05-multi-gpu-lmstudio-architecture.md` | Design specification | `docs/lmstudio-api-implementation.md` (partial) |

---

## Gateway Historical Reports

### Gateway v2 Testing Evolution

| File | Date | Status | Reason for Archive |
|------|------|--------|-------------------|
| `GATEWAY_V2_TEST_REPORT.md` | 2026-03-04 | Superseded | Early testing, blocked by LM Studio issues |
| `GATEWAY_V2_ROUTER_SUCCESS.md` | 2026-03-04 | Superseded | Router integration success, but not final |
| **`GATEWAY_V2_ALL_TESTS_PASSED.md`** | 2026-03-05 | **ACTIVE** | Definitive completion report, kept in main docs |

**Current Location:** `/etc/nixos/docs/GATEWAY_V2_ALL_TESTS_PASSED.md`

---

## Obsolete Documentation

### LM Studio Documentation (2026-03-11)

| File | Status | Reason | Replacement |
|------|--------|--------|-------------|
| `lm-studio-0.4.6-working-config-OBSOLETE-version-specific.md` | **VERSION-SPECIFIC** | Contains version 0.4.6-1 specific configuration | `docs/lm-studio-headless-setup.md`, `modules/services/lm-studio.nix` |

Version-specific documentation that becomes obsolete as LM Studio updates. The working configuration is now managed through the NixOS module and headless setup guide.

### Mining Documentation (2026-03-11)

| File | Status | Reason | Replacement |
|------|--------|--------|-------------|
| `mining-power-optimization.md` | **CONSOLIDATED** | Content merged into mining-optimization-guide | `docs/mining-optimization-guide.md` |

Power optimization content was merged into the comprehensive mining optimization guide with additional power-scaling analysis.

### Spacebot Documentation (2026-03-11)

| File | Status | Reason | Replacement |
|------|--------|--------|-------------|
| `SPACEBOT_QUICKSTART.md` | **CONSOLIDATED** | Content merged into SETUP_GUIDE | `docs/SPACEBOT_SETUP_GUIDE.md` |

The quick start content was merged into the comprehensive setup guide to eliminate duplication while preserving all useful information.

### Switch Documentation (2026-03-10)

| File | Status | Reason | Replacement |
|------|--------|--------|-------------|
| `switch-documentation-summary-OBSOLETE-incorrect-ips.md` | **INCORRECT** | Had wrong IP address mappings for switches | `docs/networking/switch-documentation-CORRECTED.md` |

**Incorrect Mappings:**
- sw1-modem: Was 10.1.1.12, **correct is 10.1.1.90**
- sw2-tv: Was 10.1.1.90, **correct is 10.1.1.95**
- sw3-upstairs: Was 10.1.1.95, **correct is 10.1.1.12**

**Current Location:** `/etc/nixos/docs/networking/switch-documentation-CORRECTED.md`

---

## Archive Policies

### When to Archive

1. **Completed Implementation Plans** - Move design/implementation pairs to `completed-plans/`
   - When feature is fully implemented and stable
   - When usage documentation exists for users

2. **Superseded Test Reports** - Move to appropriate feature archive folder
   - When newer, more comprehensive report exists
   - Keep only the final/definitive report in main docs

3. **Incorrect Documentation** - Move to `obsolete/` with descriptive suffix
   - When corrected version exists
   - Add `-OBSOLETE-` or `-INCORRECT-` suffix for clarity

4. **Deprecated Features** - Move to feature-specific archive folder
   - When feature is removed or completely replaced

### What NOT to Archive

- Active plans (still in progress)
- User-facing guides and usage documentation
- Current architecture documentation
- ROADMAP.md (living document)
- Core agent instruction files (AGENTS.md, CLAUDE.md, QWEN.md)

---

## Archive Maintenance

### Monthly Review

Check archive for:
- Files older than 6 months that can be deleted
- Completed plans that need user-facing documentation
- Superseded files that can be safely removed

### Quarterly Cleanup

- Delete obsolete files with no historical value
- Consolidate related archived files
- Update this index

---

## Searching Archived Content

### Finding Current Information

If you're looking for information and find it in the archive:

1. Check the "Current Info Location" column in the relevant section
2. Search for the feature name in main docs (`/etc/nixos/docs/`)
3. Check DOCUMENTATION_INDEX.md for organized documentation

### Example

**Q:** Where is information about NUR integration?

**A:** The completed plan is archived, but current usage info is at:
- `/etc/nixos/docs/nur-usage.md`

---

**Archive Maintained By:** Documentation cleanup process
**Last Updated:** 2026-03-11
