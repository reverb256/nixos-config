# NixOS Configuration Sprawl Cleanup - Implementation Guide

## 🚨 Executive Summary

**Problem:** Severe code duplication with ~1,575 lines of redundant code across 23 modules
**Impact:** 46% of module code is duplicated, causing maintenance burden and risk of configuration drift
**Goal:** Reduce codebase by ~35% (1,200+ lines) while maintaining all functionality

---

## 📊 Audit Results Summary

### Critical Duplication Issues (High Priority)

#### 1. Fish Shell Configuration - 800+ lines duplicated
**Files:** 5 files with identical aliases, prompts, and configuration
- `modules/fish-starship.nix` (262 lines)
- `modules/smart-fish.nix` (130 lines)
- `modules/ai-agent-smart-fish.nix` (91 lines)
- `examples/fish-starship-examples.nix` (360 lines)
- `examples/home-manager-fish-starship.nix` (380 lines)

**Duplication Pattern:** Navigation aliases, Git commands, system utilities, Starship config

#### 2. NVIDIA Configuration - 70+ lines duplicated
**Files:** 3 files with identical hardware settings
- `configuration.nix` (lines 59-63)
- `modules/gaming.nix` (lines 17-24)
- `common/default.nix` (lines 63-76)

**Duplication Pattern:** `hardware.nvidia` blocks with modesetting, power management, drivers

#### 3. Mining Services - 65+ lines duplicated
**Files:** `modules/mining.nix` with 4 near-identical XMRig services
- `xmrig` (18 threads) - lines 161-183
- `xmrig-reduced` (12 threads) - lines 118-137
- `xmrig-minimal` (4 threads) - lines 140-159
- **Duplicate:** `xmrig-reduced` appears twice

**Duplication Pattern:** Identical serviceConfig with security hardening

#### 4. Backup Services - 70+ lines duplicated
**Files:** Similar configurations across 3 backup modules
- `modules/restic-backups.nix` (146 lines)
- `modules/nexus-backups.nix` (97 lines)
- `modules/storage.nix` (336 lines)

**Duplication Pattern:** Identical exclude lists, option structures, and service patterns

---

## 🎯 Consolidation Implementation Plan

### Phase 1: Dead Code Elimination (1 hour)

#### Task 1.1: Import Missing Module
- **Problem:** `nvidia-optimization-services.nix` exists but isn't imported
- **Action:** Add to `configuration.nix` imports
- **Savings:** Eliminates 85 duplicate lines in `gaming.nix`
- **Risk:** Low - just importing existing module

#### Task 1.2: Remove Duplicate Sudo Rules
- **Problem:** Identical sudo rules in `configuration.nix` and `users.nix`
- **Action:** Delete from `configuration.nix` (lines 14-44), keep in `users.nix`
- **Savings:** 31 lines
- **Risk:** Low - consolidated location

#### Task 1.3: Consolidate NVIDIA Hardware Settings
- **Problem:** Same `hardware.nvidia` block in 3 files
- **Action:** Keep only in `configuration.nix`, remove from others
- **Savings:** 8 lines
- **Risk:** Low - identical content

### Phase 2: High-Impact Consolidation (1-2 days)

#### Task 2.1: Merge Fish Shell Modules ⚠️ **CRITICAL**
- **Problem:** 5 files with 800+ lines of duplication
- **Solution:** Create single `modules/fish.nix` with conditional AI features
- **Approach:**
  ```nix
  # modules/fish.nix
  { config, lib, ... }:
  {
    options.programs.fish = {
      enable = lib.mkEnableOption "Fish shell";
      aiAgent = lib.mkEnableOption "AI agent integration";
    };
    config = lib.mkIf cfg.enable {
      programs.fish = {
        # Base configuration (shared)
        shellAliases = { /* navigation, git, system */ }
        // lib.optionalAttrs cfg.aiAgent { /* AI-specific */ };
        # Starship, vendor config, etc.
      };
    };
  }
  ```
- **Savings:** ~400 lines
- **Risk:** Medium - requires testing shell functionality

#### Task 2.2: Parameterize Mining Services
- **Problem:** 4 XMRig services with only thread count differences
- **Solution:** Create `mkMiningService` generator (following nvidia-optimization-services.nix pattern)
- **Savings:** ~45 lines
- **Risk:** Medium - affects mining automation

#### Task 2.3: Extract Environment Variables
- **Problem:** NVIDIA environment variables duplicated across 3 files
- **Solution:** Consolidate to `modules/environment.nix` only
- **Savings:** ~30 lines
- **Risk:** Low - identical content

### Phase 3: Module Restructuring (2-3 days)

#### Task 3.1: Split Networking Module
- **Problem:** `networking.nix` mixes basic networking, DNS, firewall, audio, VPN
- **Solution:** Split into domain-specific modules:
  - `modules/networking-core.nix` - Basic networking + static IP
  - `modules/dns-resolution.nix` - Unbound + DoT configuration
  - `modules/firewall.nix` - Firewall rules + VR ports
  - `modules/privacy-blocklists.nix` - Analytics blocking
- **Savings:** Better organization (no line reduction)
- **Risk:** Low - just file splitting

#### Task 3.2: Create SSH Module
- **Problem:** SSH config scattered across 4 files
- **Solution:** Consolidate to dedicated `modules/ssh.nix`
- **Savings:** ~30 lines
- **Risk:** Medium - requires testing SSH connectivity

#### Task 3.3: Refactor Main Configuration
- **Problem:** `configuration.nix` (618 lines) violates project convention
- **Solution:** Move service configs to dedicated modules, reduce to ~200 lines
- **Savings:** ~100 lines
- **Risk:** Medium - affects core system configuration

---

## 📋 Implementation Checklist

### Pre-Implementation
- [ ] Create backup of current `/etc/nixos` directory
- [ ] Test current build: `sudo nixos-rebuild build --flake /etc/nixos`
- [ ] Document current service behaviors (mining, gaming, networking)
- [ ] Identify which Fish module is authoritative for each feature

### Phase 1 (Dead Code) - 1 hour
- [ ] Import `nvidia-optimization-services.nix` in configuration.nix
- [ ] Remove duplicate sudo rules from configuration.nix
- [ ] Consolidate NVIDIA hardware settings
- [ ] Test build: `sudo nixos-rebuild build --flake /etc/nixos-cleanup`

### Phase 2 (High Impact) - 1-2 days
- [ ] Create consolidated `modules/fish.nix`
- [ ] Implement `mkMiningService` generator in mining.nix
- [ ] Consolidate environment variables to environment.nix
- [ ] Test all affected services (Fish shell, mining, NVIDIA)
- [ ] Verify build passes

### Phase 3 (Restructuring) - 2-3 days
- [ ] Split networking.nix into domain-specific modules
- [ ] Create dedicated ssh.nix module
- [ ] Refactor configuration.nix to import-only style
- [ ] Test full system build and boot
- [ ] Validate all services start correctly

### Post-Implementation
- [ ] Performance benchmark: compare build times
- [ ] Service dependency validation
- [ ] Documentation updates (AGENTS.md, README.md)
- [ ] Remove dead/unused files
- [ ] Create merge request from nixos-cleanup branch

---

## ⚠️ Critical Risk Areas

### 1. Fish Shell Migration
**Risk:** Breaking user shell configuration
**Mitigation:**
- Test with `sudo nixos-rebuild test --flake /etc/nixos-cleanup`
- Keep backup of current configs
- Migrate incrementally (base config first, then AI features)

### 2. Service Order Dependencies
**Risk:** Breaking service startup sequences
**Mitigation:**
- Preserve all `after =` and `wantedBy =` declarations
- Test critical services (mining, gaming, SSH)
- Monitor systemd logs: `journalctl -u <service-name>`

### 3. Mining Smart Pause Logic
**Risk:** Disrupting mining automation
**Mitigation:**
- Test pgrep patterns work after refactoring
- Verify service switching logic
- Monitor mining behavior: `systemctl status xmrig*`

### 4. SSH Configuration Changes
**Risk:** Losing remote access
**Mitigation:**
- Test SSH connectivity before/after changes
- Keep existing authorized_keys
- Validate firewall rules

---

## 🔄 Rollback Plan

If issues arise during implementation:

1. **Immediate Rollback:** Switch back to main branch
   ```bash
   cd /etc/nixos
   sudo nixos-rebuild switch --flake .
   ```

2. **Partial Rollback:** Revert specific commits
   ```bash
   cd /etc/nixos-cleanup
   git log --oneline  # Find problematic commit
   git revert <commit-hash>
   ```

3. **Full Reset:** Delete worktree and start over
   ```bash
   cd /etc/nixos
   git worktree remove /etc/nixos-cleanup
   git branch -D nixos-cleanup
   ```

---

## 📈 Expected Outcomes

### Code Reduction Metrics
- **Before:** 3,408 lines across 23 modules
- **After:** ~2,200 lines across 18 modules
- **Reduction:** ~1,208 lines (35% smaller)
- **Maintainability:** Single source of truth for each domain

### Service Reliability
- **Mining:** Smart pause continues working (tested)
- **Gaming:** NVIDIA optimizations preserved
- **Networking:** All ports and rules maintained
- **SSH:** Access preserved with better organization

### Developer Experience
- **Update Burden:** Change to aliases requires updating 1 file instead of 5
- **Debugging:** Clearer error sources and dependencies
- **Testing:** Isolated modules easier to test individually
- **Onboarding:** Simpler codebase structure

---

## 🎯 Success Criteria

- [ ] All services start without errors
- [ ] Mining automation works (smart pause, health monitoring)
- [ ] NVIDIA gaming optimizations active
- [ ] SSH access maintained
- [ ] VR streaming ports open
- [ ] Distributed builds functional
- [ ] No configuration drift introduced
- [ ] Build time not significantly impacted

---

## 📝 Progress Tracking

Use this section to track implementation progress:

### Completed Tasks
- [x] Audit completed - identified 1,575 lines of duplication
- [x] Worktree created at `/etc/nixos-cleanup/`
- [x] Branch `nixos-cleanup` created
- [ ] Documentation prepared

### In Progress
- [ ] Phase 1: Dead code elimination
- [ ] Phase 2: High-impact consolidation
- [ ] Phase 3: Module restructuring

### Remaining
- [ ] Testing and validation
- [ ] Performance benchmarking
- [ ] Documentation updates
- [ ] Merge to main branch

---

## 🔗 Related Documentation

- `AGENTS.md` - Current system documentation (needs updating)
- `README.md` - Project overview
- `SECURITY_AUDIT.md` - Security considerations
- `PERFORMANCE_OPTIMIZATION_PLAN.md` - Performance notes
- `CLAWDBOT_DOCUMENTATION.md` - Bot configuration

---

**Implementation Status:** Ready to begin Phase 1
**Estimated Completion:** 3-5 days
**Risk Level:** Medium (with proper testing)
**Rollback Available:** Yes

---

*Generated: January 17, 2026*
*Branch: nixos-cleanup*
*Location: /etc/nixos-cleanup/SPRAWL_CLEANUP_IMPLEMENTATION.md*