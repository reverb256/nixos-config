# CLAUDE.md Updates - NixOS-Specific Warnings

**Date:** 2026-03-25 | **Purpose:** Clarify that this is NixOS, not typical Linux

---

## Summary

Updated `CLAUDE.md` with comprehensive NixOS-specific warnings to prevent imperative configuration mistakes that break the declarative model.

---

## Changes Made

### 1. Added Critical Warning Section

**Location:** Top of CLAUDE.md (lines 2-24)

**Content:**
- ⚠️ **CRITICAL: THIS IS NIXOS** banner
- Clear distinction between declarative (NixOS) vs imperative (typical Linux)
- Mandatory configuration rules table (CORRECT vs FORBIDDEN)
- Consequences of breaking rules (unreproducible system, broken rollbacks)

**Key Warnings:**
```markdown
❌ FORBIDDEN:
- NEVER install packages with nix-env -iA package
- NEVER modify /etc/nix directly (it's the Nix store - immutable)
- NEVER use systemctl start/enable for persistent services
- NEVER edit files in /etc outside of NixOS management
```

---

### 2. NixOS Declarative Model Section

**Location:** Lines 36-69

**Content:**
- Comparison table: Correct (NixOS) vs Wrong (Imperative) actions
- Table covers: packages, services, users, config files, system changes
- Why this matters: reproducibility, rollback, documentation, safety

**Example Table:**
| Action | ✅ CORRECT (NixOS) | ❌ WRONG (Imperative) |
|--------|-------------------|---------------------|
| Install packages | Edit `environment.systemPackages` | `nix-env -iA package` |
| Enable services | Edit `services.<name>.enable = true` | `systemctl enable <service>` |
| Start services | `nixos-rebuild switch` | `systemctl start <service>` |

---

### 3. NixOS Store vs Configuration

**Location:** Lines 71-109

**Content:**
- Critical distinction: `/etc/nixos/` (config) vs `/nix` (store)
- Path comparison table showing mutability and management
- Key points explaining the relationship
- Example showing correct vs wrong workflow

**Key Distinction:**
| Path | Purpose | Mutable? | Managed By |
|------|---------|----------|-----------|
| `/etc/nixos/` | NixOS configuration (source code) | ✅ Yes | You (edit files) |
| `/nix` | Nix store (built packages) | ❌ No | Nix (immutable) |

---

### 4. NixOS Generations and Rollback

**Location:** Lines 111-133

**Content:**
- Explanation of NixOS generations (created by each rebuild)
- Commands for viewing, rolling back, and cleaning up generations
- Boot menu explanation (GRUB2 shows all generations)
- Disaster recovery use case

**Commands Added:**
```bash
nixos-rebuild list-generations  # View all generations
nixos-rebuild rollback            # Rollback to previous
nixos-rebuild switch --profile    # Rollback to specific
nix-collect-garbage -d            # Cleanup old generations
```

---

### 5. NixOS-Specific Conventions

**Location:** Lines 135-219

**Content:**
- Declarative system configuration examples
- Package management (correct vs wrong)
- Configuration files (generated vs edited)
- User management (declarative vs imperative)

**Examples Provided:**
```nix
# ✅ CORRECT: Define service in NixOS module
{ config, pkgs, ... }: {
  services.my-service = {
    enable = true;
    settings.port = 8080;
  };
}
```

```bash
# ❌ WRONG: Imperative service management
systemctl start my-service  # Won't survive reboot
```

---

### 6. Updated Project Structure

**Location:** Lines 248-265

**Content:**
- Clarified that ALL system configuration must be in `/etc/nixos/`
- Added forbidden paths warning (`/nix`, `/etc/nix`)
- Correct workflow emphasized (edit → test → commit → deploy)

**Workflow Emphasized:**
1. Edit `/etc/nixos/modules/` or host configs
2. Test: `nixos-rebuild test` (can rollback)
3. Commit: `git add` && `git commit`
4. Deploy: `just deploy` (Colmena via NFS)

---

### 7. NixOS Rebuild Commands

**Location:** Lines 267-294

**Content:**
- Added NixOS rebuild safety section
- Before deploying checklist (validate, test, verify, deploy)
- If something breaks: rollback immediately
- NixOS rebuild commands reference table

**Commands Added:**
```bash
nixos-rebuild test     # Test on current host (can rollback)
nixos-rebuild switch   # Apply to current host (new generation)
nixos-rebuild rollback # Rollback to previous generation
```

---

## Impact

### Before Updates
- CLAUDE.md mentioned NixOS but didn't emphasize declarative nature
- No explicit warnings against imperative methods
- No explanation of `/etc/nixos/` vs `/nix` distinction
- No guidance on NixOS generations and rollback

### After Updates
- ⚠️ **CRITICAL** banner at top of file
- Comprehensive comparison tables (correct vs wrong)
- Clear explanation of NixOS store vs configuration
- Complete NixOS rebuild safety guide
- 200+ lines of NixOS-specific warnings and examples

---

## Prevention

**These updates prevent:**
1. **Package installation errors** - Users won't use `nix-env` (breaks reproducibility)
2. **Service management errors** - Users won't use `systemctl enable` (won't survive rebuilds)
3. **Configuration drift** - All changes go through NixOS config
4. **Rollback failures** - Imperative changes break rollback capability
5. **Deployment failures** - All state is declarative and reproducible

---

## Compliance

**AGENTS.md Compliance:**
- ✅ Declarative configuration (all state in NixOS modules)
- ✅ Proper workflow (edit → test → commit → deploy)
- ✅ Rollback safety (generations and recovery)

**CLAUDE.md Compliance:**
- ✅ NixOS-specific warnings (imperative methods forbidden)
- ✅ Store vs config distinction (/etc/nixos vs /nix)
- ✅ Rebuild safety (test before deploy, rollback if broken)

---

## References

**NixOS Documentation:**
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [NixOS Concepts](https://nixos.org/manual/nixos/stable/#ch-basic-configuration)

**Internal Documentation:**
- `AGENTS.md` - Universal patterns for all agents
- `modules/default.nix` - Module imports and structure
- `flake.nix` - Nix flake configuration

---

**Document Owner:** j_kro
**Version:** 1.0 | **Created:** 2026-03-25
**Status:** ✅ CLAUDE.md updated with NixOS-specific warnings
